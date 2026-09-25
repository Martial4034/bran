import Foundation
import Observation

/// Le seul réglage des gestes qui appartienne à bran : les allumer ou non.
///
/// **Tout le reste vit dans `GestureSettings.shared`**, du paquet SwishClone —
/// seuils, zone active, durée d'animation, swipe et pinch séparément. bran
/// n'en fait pas une copie : la section des réglages pilote directement ces
/// valeurs-là, que les moniteurs relisent à chaque geste. Deux réglages pour
/// une même valeur, c'est la garantie qu'un jour ils divergent.
///
/// L'interrupteur, lui, ne peut pas vivre là-bas : l'app SwishClone n'en a pas
/// — elle est la fonction, elle n'a rien d'autre à faire — alors que bran en a
/// une douzaine.
@MainActor
@Observable
final class GesturesSettings {

    private enum Key {
        static let isEnabled = "bran.gestures.isEnabled"
    }

    /// Éteint par défaut, et c'est la même raison que pour l'éveil au
    /// lancement : une application qui se met à ranger vos fenêtres au premier
    /// swipe sur une barre de titre, sans qu'on le lui ait demandé, est une
    /// application qu'on désinstalle — après avoir cherché une semaine pourquoi
    /// Safari changeait de taille tout seul.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    private let defaults = UserDefaults.standard

    init() {
        isEnabled = defaults.bool(forKey: Key.isEnabled)
    }
}
