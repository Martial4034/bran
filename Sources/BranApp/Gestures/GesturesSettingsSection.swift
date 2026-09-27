import SwiftUI

/// Les gestes, dans « Général » : **un renvoi**, plus un réglage.
///
/// Tout a déménagé dans la section « Trackpad » de la fenêtre principale —
/// l'interrupteur, les gestes un par un, les options et les réglages fins. Un
/// geste se montre mieux qu'il ne s'écrit, et une feuille de réglages n'a pas
/// la place de le montrer.
///
/// La ligne reste ici pour qui cherche « gestes » dans les réglages par
/// habitude : elle dit où c'est, et y mène.
struct GesturesSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Gestes du trackpad") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(model.gestures.settings.isEnabled ? "Activés" : "Désactivés")
                    Text("Les gestes, leur activation un par un et leurs réglages fins ont leur page.")
                        .font(Type.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Ouvrir la page Trackpad") { openTrackpad() }
            }
        }
    }

    /// `LibraryView` lit la section par `@AppStorage` : l'écrire puis fermer
    /// la feuille suffit.
    private func openTrackpad() {
        UserDefaults.standard.set(LibraryPane.trackpad.rawValue, forKey: LibraryPane.defaultsKey)
        model.showsSettings = false
    }
}
