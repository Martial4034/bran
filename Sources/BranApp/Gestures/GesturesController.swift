import Foundation
import Observation
import SwishGestures

/// **Les gestes du trackpad : un interrupteur, et la vérité sur ce qui tourne.**
///
/// ```
///   réglage allumé ──▶ GestureMonitor.start() ──▶ un tap d'écoute seule, sur son propre thread,
///                                            │     qui suit swipe et pincement d'un bout à l'autre
///                                            └─▶ échec ──▶ `problem`, réglage intact
///   retour au premier plan ──▶ nouvel essai, si allumé et arrêté
///   fermeture de bran ──▶ `shutdown()` : le thread du tap est joint, le verrou d'hôte libéré
/// ```
///
/// La détection elle-même — la machine à états, l'aperçu, les actions sur les
/// fenêtres et sur le Dock — est dans SwishClone et n'est pas redite ici. Ce
/// contrôleur ne fait que ce qu'un hôte doit faire : décider quand démarrer,
/// et dire honnêtement si ça tourne.
///
/// **Un échec ne remet pas l'interrupteur sur « non »**, à la différence de la
/// capture. Les échecs ordinaires se règlent hors de bran — l'Accessibilité
/// s'accorde dans les Réglages système, une autre app de gestes se quitte — et
/// `retryIfNeeded()` redémarre au retour au premier plan : l'utilisateur n'a
/// pas à se souvenir de rallumer un réglage qu'il n'a jamais éteint. En
/// attendant, `problem` dit pourquoi rien ne se passe — l'interrupteur dit
/// l'intention, la phrase dit l'état, comme pour l'éveil.
@MainActor
@Observable
final class GesturesController {

    /// Pourquoi la détection ne tourne pas alors qu'elle est demandée. Un cas
    /// par cause, parce que chacune a sa sortie : un bouton vers les Réglages,
    /// un « Réessayer », ou rien.
    enum Problem: Equatable {
        case accessibilityMissing
        /// Un autre processus (l'app de test SwishClone, une autre copie de
        /// bran) tient déjà la détection. Deux hôtes suivraient le même geste
        /// et agiraient chacun sur la même fenêtre : SwishGestures refuse le
        /// second. `holder` nomme le détenteur, pour le dire à l'utilisateur.
        case anotherHost(holder: String)
        case listeningRefused

        var message: String {
            switch self {
            case .accessibilityMissing:
                return "En attente de l'autorisation d'Accessibilité."
            case let .anotherHost(holder):
                return "Une autre app de gestes est déjà active (\(holder)). Quittez-la, puis réessayez."
            case .listeningRefused:
                // `eventTapUnavailable` avec l'Accessibilité accordée : le tap
                // du raccourci de bran, lui, se crée avec la même autorisation.
                // Si celui-ci échoue, c'est que macOS a changé quelque chose —
                // le dire plutôt que proposer une case à cocher qui ne
                // réglerait rien.
                return "macOS a refusé l'écoute du trackpad. Relancer bran peut suffire."
            }
        }
    }

    let settings: GesturesSettings

    /// `nil` quand tout va bien, ou quand la détection est éteinte.
    private(set) var problem: Problem?

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
    /// Réglages système (l'Accessibilité vient peut-être d'être accordée), ou
    /// d'avoir quitté l'autre app de gestes. Ne fait rien si la détection
    /// tourne déjà ou n'est pas voulue.
    func retryIfNeeded() {
        guard settings.isEnabled, isRunning == false else { return }
        apply()
    }

    /// Le bouton « Réessayer » : même chose, à la demande.
    func retry() {
        retryIfNeeded()
    }

    /// À la fermeture de bran : joint le thread du tap, libère le verrou
    /// d'hôte. Ne touche pas au réglage — la prochaine ouverture repart de
    /// l'intention de l'utilisateur.
    func shutdown() {
        GestureMonitor.stop()
        isRunning = false
    }

    /// La phrase du menu et des réglages.
    var summary: String {
        if let problem { return problem.message }
        return isRunning
            ? "Actifs sur les barres de titre et les icônes du Dock."
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
            problem = .accessibilityMissing
            FeatureLog.record("gestes — Accessibilité manquante")
        } catch GestureMonitor.StartError.anotherHostRunning(let processID, let name) {
            let holder = [name, processID.map { "pid \($0)" }].compactMap { $0 }.joined(separator: ", ")
            problem = .anotherHost(holder: holder.isEmpty ? "autre processus" : holder)
            FeatureLog.record("gestes — déjà actifs dans un autre processus (\(holder))")
        } catch {
            problem = .listeningRefused
            FeatureLog.record("gestes — écoute du trackpad refusée")
        }
        isRunning = GestureMonitor.isRunning
    }
}
