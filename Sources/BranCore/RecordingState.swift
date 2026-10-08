/// États de `RecordingEngine`.
///
/// `.finalizing` couvre l'arrêt du flux, et lui seul : quelques dizaines de
/// millisecondes. L'écriture du `.mp4` par `replayd`, qui dure un tiers de la
/// réunion, ne se passe plus dans la session mais dans le post-traitement —
/// voir `CaptureBackend.stop()`. C'est ce qui permet de démarrer la réunion
/// suivante pendant que la précédente s'écrit encore.
public enum RecordingState: Equatable, Sendable {
    case idle
    case starting(MeetingRef)
    case recording(MeetingRef)

    /// Segment courant fermé, session toujours ouverte.
    ///
    /// ScreenCaptureKit n'a pas de pause : `SCStream` n'expose que
    /// `startCapture` / `stopCapture`, et `updateConfiguration` sur un flux qui
    /// enregistre l'interrompt. La pause est donc une fermeture de fichier, et
    /// la reprise l'ouverture d'un nouveau. Les morceaux sont recollés à la fin.
    case paused(MeetingRef)

    case finalizing(MeetingRef)
    case failed(reason: String)

    public var meeting: MeetingRef? {
        switch self {
        case .starting(let meeting), .recording(let meeting),
             .paused(let meeting), .finalizing(let meeting):
            meeting
        case .idle, .failed:
            nil
        }
    }

    public var isActive: Bool {
        switch self {
        case .starting, .recording, .paused, .finalizing: true
        case .idle, .failed: false
        }
    }
}
