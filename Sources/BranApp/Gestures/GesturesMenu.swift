import SwiftUI

/// Les gestes dans le menu de bran : **un interrupteur et une phrase**.
///
/// ```
///   ☑ Gestes du trackpad
///     Actifs sur la barre de titre de la fenêtre au premier plan.
/// ```
///
/// Rien d'autre : les seuils et la zone se règlent une fois et ne se
/// retouchent plus, ils vivent dans les réglages. Le menu sert au geste
/// qu'on fait vraiment — couper les gestes le temps d'une présentation.
struct GesturesMenu: View {
    let gestures: GesturesController

    var body: some View {
        Toggle(isOn: Binding(
            get: { gestures.settings.isEnabled },
            set: { gestures.setEnabled($0) }
        )) {
            Text("Gestes du trackpad")
        }

        // Seulement quand il y a quelque chose à dire. « Éteints » sous une
        // case décochée répéterait la case ; un problème, lui, est
        // précisément ce que la case ne montre pas.
        if gestures.settings.isEnabled {
            Text(gestures.summary)
        }
    }
}
