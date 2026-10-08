import AVFoundation
import Foundation
import ScreenCaptureKit

/// Peut-on ouvrir une capture pendant que `replayd` finalise la précédente ?
///
/// Le 08/10/2026, deux closings s'enchaînaient (14h30–15h, puis 15h). bran a
/// refusé de démarrer le second pendant cinq à six minutes : la session restait
/// en `.finalizing` tant que `replayd` écrivait le premier fichier — 93 % du
/// fichier s'écrit après `stopCapture()`, voir `FinalizationWatch`. Sortir la
/// finalisation de la session suppose que ScreenCaptureKit accepte un second
/// `SCStream` + `SCRecordingOutput` pendant ce temps, **sans abîmer aucun des
/// deux fichiers**. Rien dans les en-têtes ne le dit. Si la réponse est non, la
/// file d'attente en arrière-plan n'est pas écrite.
///
/// Deux modes, à comparer :
/// - `--solo` : A seule, la finalisation mesurée sans concurrence (témoin) ;
/// - par défaut : A, arrêt, B ouverte **sans attendre** la fin de A.
///
/// Ne lit jamais le contenu capturé : seuls des tailles, des durées et des
/// comptes d'échantillons sont imprimés.
struct OverlapSpike {
    let first: Duration
    let second: Duration
    let scale: Double
    let solo: Bool
    let folder: URL

    func run() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ProbeError.screenRecordingDenied
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let clock = ContinuousClock()
        let origin = clock.now
        func t() -> String {
            let seconds = Double((clock.now - origin).components.seconds)
                + Double((clock.now - origin).components.attoseconds) / 1e18
            return "t+\(seconds.formatted(.number.precision(.fractionLength(1))))s"
        }

        let urlA = folder.appending(path: "overlap-A-\(FileStamp.now).mp4")
        let a = try await Capture.open(at: urlA, scale: scale)
        print("\(t()) A ouverte → \(urlA.lastPathComponent)")

        try await a.state.waitUntil(deadline: .now + first) { $0.failure != nil }
        let stopRequested = clock.now
        try await a.stream.stopCapture()
        let sizeAtStop = Self.size(urlA)
        print("\(t()) A stopCapture() rendu en \(clock.now - stopRequested) — \(Self.bytes(sizeAtStop)) écrits")

        var b: Capture?
        var urlB: URL?
        var bStopped = false
        var bOpenedAt: ContinuousClock.Instant?
        var aFinishedAt: ContinuousClock.Instant?
        var lastLog = clock.now

        if solo == false {
            let url = folder.appending(path: "overlap-B-\(FileStamp.now).mp4")
            let opening = clock.now
            b = try await Capture.open(at: url, scale: scale)
            urlB = url
            bOpenedAt = clock.now
            print("\(t()) B ouverte en \(clock.now - opening) pendant la finalisation de A")
        }

        // Une seule boucle pour les deux : A se finalise pendant que B tourne,
        // et c'est précisément l'entrelacement qu'on veut voir.
        let deadline = clock.now + .seconds(1800)
        while clock.now < deadline {
            if aFinishedAt == nil, a.state.snapshot.didFinish || a.state.snapshot.failure != nil {
                aFinishedAt = clock.now
                print("\(t()) A \(a.state.snapshot.didFinish ? "finalisée" : "EN ÉCHEC : \(a.state.snapshot.failure!.line)") après \(clock.now - stopRequested) — \(Self.bytes(Self.size(urlA)))")
            }
            if let b, let bOpenedAt, bStopped == false {
                if let failure = b.state.snapshot.failure {
                    print("\(t()) B EN ÉCHEC pendant la capture : \(failure.line)")
                    bStopped = true
                } else if clock.now - bOpenedAt >= second {
                    let requested = clock.now
                    try await b.stream.stopCapture()
                    bStopped = true
                    print("\(t()) B stopCapture() rendu en \(clock.now - requested) — \(Self.bytes(Self.size(urlB!)))")
                }
            }
            let bDone = b.map { $0.state.snapshot.didFinish || $0.state.snapshot.failure != nil } ?? true
            if aFinishedAt != nil, bStopped || b == nil, bDone { break }

            if clock.now - lastLog >= .seconds(10) {
                lastLog = clock.now
                var line = "\(t()) A \(Self.bytes(Self.size(urlA)))"
                if let urlB { line += " · B \(Self.bytes(Self.size(urlB)))" }
                print(line)
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        print()
        try await Self.report(urlA, label: "A", recorded: first)
        if let urlB { try await Self.report(urlB, label: "B", recorded: second) }
    }

    // MARK: - Capture

    struct Capture {
        let stream: SCStream
        let output: SCRecordingOutput
        let delegate: CaptureSpikeDelegate
        let state: CaptureState
        let consumer: Task<Void, Never>

        /// Configuration recopiée de `CaptureSession.openSegment()` : la mesure
        /// ne vaut que pour les réglages de production.
        static func open(at url: URL, scale: Double) async throws -> Capture {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw CaptureSpikeError.noDisplay }
            print("  écran capturé \(display.width)×\(display.height) pts (id \(display.displayID), principal \(CGMainDisplayID() == display.displayID ? "oui" : "non"))")
            let own = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own.map { [$0] } ?? [], exceptingWindows: [])

            let configuration = SCStreamConfiguration()
            configuration.width = even(Double(display.width) * scale)
            configuration.height = even(Double(display.height) * scale)
            configuration.captureResolution = scale > 1 ? .best : .nominal
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = true
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
            configuration.captureMicrophone = true
            configuration.captureDynamicRange = .SDR

            let recording = SCRecordingOutputConfiguration()
            recording.outputURL = url
            recording.outputFileType = .mp4
            recording.videoCodecType = .hevc

            let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
            let delegate = CaptureSpikeDelegate(continuation: continuation)
            let state = CaptureState()
            let consumer = Task {
                for await event in events { state.record(event) }
            }

            let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
            let output = SCRecordingOutput(configuration: recording, delegate: delegate)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            return Capture(stream: stream, output: output, delegate: delegate, state: state, consumer: consumer)
        }

        private static func even(_ value: Double) -> Int {
            let rounded = Int(value.rounded())
            return rounded.isMultiple(of: 2) ? rounded : rounded + 1
        }
    }

    // MARK: - Verdict

    /// Durées par piste et nombre d'échantillons vidéo, lus sans décoder.
    ///
    /// L'audio est continu : une piste audio plus courte que le temps enregistré
    /// est le signe le plus fiable d'un trou. La vidéo, elle, n'émet d'images
    /// que quand l'écran change — son compte ne se compare qu'entre deux runs.
    static func report(_ url: URL, label: String, recorded: Duration) async throws {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let video = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        var line = "\(label) : lisible \(playable ? "oui" : "NON") · \(duration.formatted(.number.precision(.fractionLength(1)))) s"
        line += " pour \(recorded.components.seconds) s demandées · \(bytes(size(url)))"
        line += " · \(video.count) vidéo / \(audio.count) audio"
        print(line)

        for track in audio {
            let range = try await track.load(.timeRange)
            print("  audio \(range.duration.seconds.formatted(.number.precision(.fractionLength(2)))) s")
        }
        for track in video {
            let range = try await track.load(.timeRange)
            let samples = countSamples(asset: asset, track: track)
            print("  vidéo \(range.duration.seconds.formatted(.number.precision(.fractionLength(2)))) s · \(samples) images")
        }
    }

    private static func countSamples(asset: AVAsset, track: AVAssetTrack) -> Int {
        guard let reader = try? AVAssetReader(asset: asset) else { return -1 }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return -1 }
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            count += CMSampleBufferGetNumSamples(buffer)
        }
        return reader.status == .completed ? count : -count
    }

    static func size(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? Int64 ?? 0
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }
}
