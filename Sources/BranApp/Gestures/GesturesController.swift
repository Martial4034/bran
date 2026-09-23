import Foundation
import Observation
import SwishGestures

/// **Les gestes du trackpad : un interrupteur, et la vérité sur ce qui tourne.**
///
/// ```
///   réglage allumé ──▶ GestureMonitor.start() ──▶ swipe (NSEvent) + pinch (CGEventTap)
///                                            └─▶ échec ──▶ `problem`, réglage intact
///   retour au premier plan ──▶ nouvel essai, si allumé et arrêté
/// ```
///
/// La détection elle-même — les moniteurs, la zone de la barre de titre, les
/// actions sur les fenêtres — est dans SwishClone et n'est pas redite ici. Ce
/// contrôleur ne fait que ce qu'un hôte doit faire : décider quand démarrer,
/// et dire honnêtement si ça tourne.
///
/// **Un échec ne remet pas l'interrupteur sur « non »**, à la différence de la
/// capture. Le seul échec ordinaire est l'Accessibilité manquante, et elle se
/// règle hors de bran : on revient des Réglages système, `retryIfNeeded()`
/// redémarre, et l'utilisateur n'a pas à se souvenir de rallumer un réglage
/// qu'il n'a jamais éteint. En attendant, `problem` dit pourquoi rien ne se
/// passe — l'interrupteur dit l'intention, la phrase dit l'état, comme pour
/// l'éveil.
@MainActor
@Observable
final class GesturesController {

    let settings: GesturesSettings

    /// Ce qui empêche la détection de tourner alors qu'elle est demandée.
    /// `nil` quand tout va bien, ou quand elle est éteinte.
    private(set) var problem: String?

    /// Recopié de `GestureMonitor.isRunning` après chaque changement :
    /// `GestureMonitor` n'est pas observable, et la vue doit se rafraîchir.
    private(set) var isRunning = false

    init(settings: GesturesSettings) {
        self.settings = settings
    }

    /// Appelé une fois par `AppModel`, au lancement.
    func start() {
        apply()
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        apply()
    }

    /// Appelé au retour au premier plan — c'est le moment où l'on revient des
    /// Réglages système, donc celui où l'Accessibilité vient peut-être d'être
    /// accordée. Ne fait rien si la détection tourne déjà ou n'est pas voulue.
    func retryIfNeeded() {
        guard settings.isEnabled, isRunning == false else { return }
        apply()
    }

    /// La phrase du menu et des réglages.
    var summary: String {
        if let problem { return problem }
        return isRunning
            ? "Actifs sur la barre de titre de la fenêtre au premier plan."
            : "Éteints."
    }

    private func apply() {
        guard settings.isEnabled else {
            if GestureMonitor.isRunning { FeatureLog.record("gestes — arrêtés") }
            GestureMonitor.stop()
            problem = nil
            isRunning = false
            return
        }

        do {
            try GestureMonitor.start()
            if problem != nil || isRunning == false { FeatureLog.record("gestes — démarrés") }
            problem = nil
        } catch GestureMonitor.StartError.accessibilityNotTrusted {
            problem = "En attente de l'autorisation d'Accessibilité."
            FeatureLog.record("gestes — Accessibilité manquante")
        } catch {
            // `eventTapUnavailable` avec l'Accessibilité accordée : le tap du
            // raccourci de bran, lui, se crée avec la même autorisation. Si
            // celui-ci échoue, c'est que macOS a changé quelque chose — le dire
            // plutôt que proposer une case à cocher qui ne réglerait rien.
            problem = "macOS a refusé l'écoute du trackpad. Relancer bran peut suffire."
            FeatureLog.record("gestes — écoute du trackpad refusée")
        }
        isRunning = GestureMonitor.isRunning
    }
}
