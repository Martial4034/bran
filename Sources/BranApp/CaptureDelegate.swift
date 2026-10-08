import Foundation
import ScreenCaptureKit

/// `SCStreamDelegate` et `SCRecordingOutputDelegate` sont des protocoles
/// Objective-C rappelés sur une queue arbitraire.
///
/// `@unchecked Sendable` justifié : les deux seules propriétés stockées sont
/// elles-mêmes `Sendable` et gèrent leur propre synchronisation. Il n'y a aucun
/// état mutable non protégé dans cette classe.
final class CaptureDelegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private let signals: CaptureSignals
    private let failures: AsyncStream<String>.Continuation

    init(signals: CaptureSignals, failures: AsyncStream<String>.Continuation) {
        self.signals = signals
        self.failures = failures
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        signals.markFinished()
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        report("écriture du fichier interrompue : \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        report("flux de capture interrompu : \(error.localizedDescription)")
    }

    /// **Une panne ne remonte à la session que si elle la concerne.**
    ///
    /// Une fois l'arrêt demandé, ce delegate appartient à un segment qui
    /// s'écrit en arrière-plan, et la session de `CaptureSession` est
    /// peut-être déjà celle de la réunion suivante. Remonter la panne par
    /// `failures` la ferait conclure par `RecordingEngine.reportFailure` —
    /// une réunion en cours coupée pour un fichier qui n'est pas le sien. La
    /// panne reste inscrite dans `signals`, que l'attente de finalisation lit :
    /// c'est par là qu'elle se dit, sur la bonne réunion.
    private func report(_ reason: String) {
        let concernsLiveSession = signals.isRecording
        signals.markFailed(reason)
        if concernsLiveSession { failures.yield(reason) }
    }
}
