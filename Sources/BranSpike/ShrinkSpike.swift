import AVFoundation
import Foundation
import VideoToolbox

/// Quelle vidéo suffit pour relire un closing ?
///
/// La fusion garde la pleine définition de l'écran — 5160×2160 à environ
/// 10 Mbit/s, 1,8 Go pour le closing de 30 min du 08/10/2026 — alors que ces
/// fichiers partent sur un Drive où personne ne les regardera peut-être jamais.
/// Ce banc réencode un extrait d'une vraie réunion à une hauteur et un débit
/// donnés, puis rend la taille extrapolée à 30 min, la vitesse, et une image
/// fixe pour juger le texte à l'œil.
///
/// La réduction se fait **au décodage** (`kCVPixelBufferWidthKey` sur la sortie
/// du lecteur) : le décodeur matériel rend directement des images à la bonne
/// taille, et l'encodeur n'a plus que le quart des pixels à traiter.
///
/// N'imprime aucun contenu : des tailles, des durées, et le chemin des images
/// produites, qui restent dans le dossier de sortie.
struct ShrinkSpike {
    let input: URL
    let output: URL
    let start: Double
    let seconds: Double
    let height: Int
    let bitrate: Int

    func run() async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CaptureSpikeError.noDisplay
        }
        let natural = try await track.load(.naturalSize)
        let width = Self.even(Double(height) * natural.width / natural.height)

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let name = "shrink-\(height)p-\(bitrate / 1000)k"
        let destination = output.appending(path: "\(name).mp4")
        try? FileManager.default.removeItem(at: destination)

        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let videoOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true,
            ] as [String: Any],
        ])
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)

        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(out)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 96_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioOut = out
            audioIn = input
        }

        let clock = ContinuousClock()
        let began = clock.now
        guard reader.startReading() else { throw reader.error ?? CaptureSpikeError.noDisplay }
        writer.startWriting()
        writer.startSession(atSourceTime: range.start)

        // Les objets AVFoundation ne sont pas `Sendable` ; chaque paire n'est
        // touchée que par sa propre file, d'où la boîte non vérifiée.
        let video = Lane(output: videoOut, input: videoIn)
        let audio = audioOut.flatMap { out in audioIn.map { Lane(output: out, input: $0) } }
        async let videoDone: Void = Self.pump(video, label: "vidéo")
        async let audioDone: Void = { if let audio { await Self.pump(audio, label: "audio") } }()
        _ = await (videoDone, audioDone)
        await writer.finishWriting()
        let spent = clock.now - began

        guard writer.status == .completed else {
            print("✗ \(name) : \(writer.error?.localizedDescription ?? "échec")")
            return
        }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false)))?[.size] as? Int64 ?? 0
        let perHalfHour = Double(bytes) / seconds * 1800
        let speed = seconds / (Double(spent.components.seconds) + Double(spent.components.attoseconds) / 1e18)

        // Une image fixe au milieu de l'extrait, à la définition du fichier.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let still = output.appending(path: "\(name).png")
        if let (image, _) = try? await generator.image(at: CMTime(seconds: seconds / 2, preferredTimescale: 600)),
           let destination = CGImageDestinationCreateWithURL(still as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }

        print("\(name) : \(width)×\(height) · \(Self.mb(bytes)) pour \(Int(seconds)) s → \(Self.mb(Int64(perHalfHour))) pour 30 min · \(speed.formatted(.number.precision(.fractionLength(1))))× le temps réel")
    }

    struct Lane: @unchecked Sendable {
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
    }

    private static func pump(_ lane: Lane, label: String) async {
        let output = lane.output
        let input = lane.input
        let queue = DispatchQueue(label: "shrink.\(label)")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        done.resume()
                        return
                    }
                    input.append(buffer)
                }
            }
        }
    }

    private static func even(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }

    private static func mb(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
