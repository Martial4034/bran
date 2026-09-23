import SwiftUI
import SwishGestures

/// Les réglages des gestes, dans « Général ».
///
/// **Pas un onglet**, pour la même raison que l'éveil : un interrupteur et
/// quatre curseurs ne font pas un écran.
///
/// **Deux sources, et c'est voulu.** L'interrupteur principal est à bran
/// (`GesturesSettings`) ; tout le reste pilote directement
/// `GestureSettings.shared`, du paquet SwishClone, que les moniteurs relisent
/// à chaque geste — un curseur déplacé s'applique au geste suivant, sans
/// bouton ni redémarrage. Les bornes des curseurs sont celles de la fenêtre de
/// préférences de SwishClone : elles ont été choisies là-bas, sur le trackpad,
/// et n'ont pas de raison d'être différentes ici.
struct GesturesSettingsSection: View {
    @Bindable var model: AppModel

    /// `ObservableObject` et pas `@Observable` : SwishClone vise macOS 13.
    @ObservedObject private var tuning = GestureSettings.shared

    private var gestures: GesturesController { model.gestures }

    var body: some View {
        Section("Gestes du trackpad") {
            Toggle("Gestes sur les barres de titre", isOn: Binding(
                get: { gestures.settings.isEnabled },
                set: { gestures.setEnabled($0) }
            ))

            Text("Deux doigts sur la barre de titre de la fenêtre au premier plan : glisser à gauche ou à droite la range sur la moitié de l'écran, vers le haut l'agrandit, vers le bas la réduit dans le Dock. Écarter les doigts bascule le plein écran, les resserrer la recentre en plus petit. Ailleurs, le trackpad ne change pas.")
                .font(Type.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if gestures.settings.isEnabled, let problem = gestures.problem {
                problemRow(problem)
            }

            Toggle("Glisser (gauche, droite, haut, bas)", isOn: $tuning.swipeEnabled)
            Toggle("Pincer (écarter, resserrer)", isOn: $tuning.pinchEnabled)

            sliderRow(
                "Seuil du glissement",
                value: $tuning.swipeThreshold,
                in: 5 ... 50,
                display: tuning.swipeThreshold.formatted(.number.precision(.fractionLength(0)))
            )
            sliderRow(
                "Seuil du pincement",
                value: $tuning.pinchThreshold,
                in: 0.02 ... 0.3,
                display: tuning.pinchThreshold.formatted(.number.precision(.fractionLength(2)))
            )
            Text("Plus le seuil est bas, plus le geste se déclenche facilement — et plus un défilement ordinaire risque d'en devenir un.")
                .font(Type.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sliderRow(
                "Hauteur de la zone",
                value: $tuning.gestureZoneHeight,
                in: 20 ... 100,
                display: tuning.gestureZoneHeight.formatted(.number.precision(.fractionLength(0))) + " pt"
            )
            sliderRow(
                "Durée de l'animation",
                value: $tuning.animationDuration,
                in: 0.05 ... 0.5,
                display: tuning.animationDuration.formatted(.number.precision(.fractionLength(2))) + " s"
            )
        }
    }

    /// Même présentation que le seuil du veilleur : le titre et la valeur sur
    /// une ligne, le curseur dessous. La valeur en chasse fixe, parce qu'elle
    /// change à chaque pixel de glissement.
    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.small) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .font(Type.code)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    /// L'Accessibilité manquante a un bouton ; l'autre échec n'en a pas, parce
    /// qu'aucun réglage de bran ne le résout.
    private func problemRow(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: Space.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.attention)
            VStack(alignment: .leading, spacing: Space.tight) {
                Text(problem)
                    .font(Type.cardBody)
                if HotkeyMonitor.isTrusted == false {
                    Button("Ouvrir les Réglages") { _ = SystemSettings.reRequestAccessibility() }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
