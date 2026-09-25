import SwiftUI
import SwishGestures

/// Les réglages des gestes, dans « Général ».
///
/// **Pas un onglet**, pour la même raison que l'éveil : un interrupteur et
/// quelques curseurs ne font pas un écran.
///
/// **Deux sources, et c'est voulu.** L'interrupteur principal est à bran
/// (`GesturesSettings`) ; tout le reste pilote directement
/// `GestureSettings.shared`, du paquet SwishClone, que le tap relit à chaque
/// geste — un curseur déplacé s'applique au geste suivant, sans bouton ni
/// redémarrage. Les bornes des curseurs sont celles de la fenêtre de
/// préférences de SwishClone : elles ont été choisies là-bas, sur le trackpad,
/// et n'ont pas de raison d'être différentes ici.
///
/// **Ce qu'on règle tous les jours, et ce qu'on règle une fois.** L'aperçu et
/// le retour haptique sont à la vue : c'est ce qu'on coupe quand ils gênent.
/// Le rythme des enchaînements (pause entre deux étapes, délai d'annulation)
/// se règle une fois sur son propre trackpad, puis on n'y revient plus : il est
/// dans « Avancé », replié.
struct GesturesSettingsSection: View {
    @Bindable var model: AppModel

    /// `ObservableObject` et pas `@Observable` : SwishClone vise macOS 13.
    @ObservedObject private var tuning = GestureSettings.shared

    private var gestures: GesturesController { model.gestures }

    var body: some View {
        Section("Gestes du trackpad") {
            Toggle("Gestes sur les barres de titre et le Dock", isOn: Binding(
                get: { gestures.settings.isEnabled },
                set: { gestures.setEnabled($0) }
            ))

            Text("Deux doigts sur la barre de titre d'une fenêtre : glisser à gauche ou à droite la range sur la moitié de l'écran, vers le haut l'agrandit, vers le bas la réduit dans le Dock. Enchaîner deux directions sans lever les doigts, avec une courte pause entre elles, vise un quart d'écran (↓ puis → : en bas à droite) ; deux fois la même direction verticale, une moitié haute ou basse. Écarter les doigts bascule le plein écran, les resserrer ferme la fenêtre. Sur une icône du Dock, resserrer quitte l'app. Échap annule le geste en cours. Ailleurs, le trackpad ne change pas.")
                .font(Type.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if gestures.settings.isEnabled, let problem = gestures.problem {
                problemRow(problem)
            }

            Toggle("Glisser (gauche, droite, haut, bas)", isOn: $tuning.swipeEnabled)
            Toggle("Pincer (écarter, resserrer)", isOn: $tuning.pinchEnabled)
            Toggle("Aperçu pendant le geste", isOn: $tuning.previewEnabled)
            Toggle("Retour haptique", isOn: $tuning.hapticsEnabled)

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

            DisclosureGroup("Avancé") {
                sliderRow(
                    "Pause entre deux étapes",
                    value: $tuning.stepPause,
                    in: 0.15 ... 0.5,
                    display: tuning.stepPause.formatted(.number.precision(.fractionLength(2))) + " s"
                )
                sliderRow(
                    "Délai d'annulation",
                    value: $tuning.cancelTimeout,
                    in: 0.6 ... 2,
                    display: tuning.cancelTimeout.formatted(.number.precision(.fractionLength(1))) + " s"
                )
                Text("Immobile plus longtemps que la pause, une direction est validée et on peut en enchaîner une autre sans lever les doigts. Immobile plus longtemps que le délai d'annulation, le geste est abandonné et rien n'est appliqué.")
                    .font(Type.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// Chaque cause a sa sortie : l'Accessibilité manquante un bouton vers les
    /// Réglages système, une autre app de gestes un « Réessayer » (une fois
    /// quittée), et le refus d'écoute rien — aucun réglage de bran ne le
    /// résout.
    private func problemRow(_ problem: GesturesController.Problem) -> some View {
        HStack(alignment: .top, spacing: Space.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.attention)
            VStack(alignment: .leading, spacing: Space.tight) {
                Text(problem.message)
                    .font(Type.cardBody)
                switch problem {
                case .accessibilityMissing:
                    if HotkeyMonitor.isTrusted == false {
                        Button("Ouvrir les Réglages") { _ = SystemSettings.reRequestAccessibility() }
                    }
                case .anotherHost:
                    Button("Réessayer") { gestures.retry() }
                case .listeningRefused:
                    EmptyView()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
