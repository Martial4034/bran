import Foundation

/// Frontière entre la machine à états et ScreenCaptureKit.
///
/// Elle existe pour une seule raison : rendre `RecordingEngine` testable sans
/// écran, sans permission et sans `replayd`.
public protocol CaptureBackend: Sendable {
    /// Démarre la capture et rend l'URL du fichier en cours d'écriture.
    ///
    /// Ne rend la main qu'une fois le flux réellement démarré. L'URL est
    /// retournée dès le départ pour que l'appelant puisse poser sa sentinelle
    /// avant qu'une panne devienne possible.
    func start(_ meeting: MeetingRef) async throws -> URL

    /// Ferme le segment courant. Comme `stop()`, rend la main dès que le flux
    /// est arrêté ; le fichier finit de s'écrire ensuite.
    func pause() async throws

    /// Ouvre un nouveau segment et rend son URL.
    func resume() async throws -> URL

    /// Arrête la capture. **Ne finalise pas le fichier.**
    ///
    /// Rend la main dès que le flux est arrêté : la session se ferme, et une
    /// nouvelle peut s'ouvrir. Le fichier, lui, n'est **pas** encore écrit —
    /// `replayd` en écrit 93 % après l'arrêt, pendant un tiers de la durée
    /// enregistrée (voir `FinalizationWatch`). C'est à l'implémentation d'offrir
    /// une attente séparée, que le post-traitement doit traverser avant de lire
    /// un segment : `CaptureSession.finishWriting(_:)`.
    ///
    /// Ce contrat a changé le 08/10/2026. Il exigeait de ne rendre la main
    /// qu'une fois le fichier écrit — juste pour le fichier, mais il gardait la
    /// session ouverte pendant toute la finalisation, et deux réunions
    /// enchaînées ne pouvaient pas s'enregistrer.
    func stop() async throws
}
