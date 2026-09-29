import AppKit
import BranTrackpad
import SwiftUI
import SwishCloneCore
import SwishGestures

/// **La section « Trackpad » : les gestes, montrés plutôt que décrits.**
///
/// ```
/// ┌──────────────────────────────────────────────────────────┐
/// │  Trackpad                                    ● Activés   │
/// │  Ranger vos fenêtres du bout de deux doigts.             │
/// ├──────────────────────────────────────────────────────────┤
/// │   ╭────────────────────────────────────────────────────╮ │
/// │   │  [mini-écran qui rejoue]   Ranger ses fenêtres…     │ │
/// │   │                            ( Activer les gestes )   │ │
/// │   ╰────────────────────────────────────────────────────╯ │
/// │   GLISSER SUR LA BARRE DE TITRE           Tout couper    │
/// │   ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                    │
/// │   │ ▣    │ │    ▣ │ │ ▣▣▣▣ │ │  ↓   │   une carte par    │
/// │   │ ← ✓  │ │ → ✓  │ │ ↑ ✓  │ │ ↓ ○  │   geste : cliquer  │
/// │   └──────┘ └──────┘ └──────┘ └──────┘   l'active ou le   │
/// │   ENCHAÎNER DEUX DIRECTIONS · PINCER · DOCK   coupe      │
/// │   FENÊTRES LIÉES (pleine largeur)                        │
/// │   PENDANT LE GESTE : aperçu · retour haptique            │
/// │   ▸ Avancé : seuils, zone, animation, rythme             │
/// └──────────────────────────────────────────────────────────┘
/// ```
///
/// ## Pourquoi une section, et plus un coin des réglages
///
/// Les gestes ne se devinent pas : personne ne tente « ↓ puis → » sur une
/// barre de titre par hasard. Une phrase de six lignes dans « Général » les
/// énumérait sans les faire voir. Ici chaque geste a son dessin, qui rejoue le
/// mouvement au survol — la leçon des Réglages système › Trackpad, et de
/// Swish, où l'on clique sur un geste pour l'activer ou le couper.
///
/// ## Aucun interrupteur, et c'est voulu
///
/// Une carte **est** son interrupteur : cliquer dessus l'active ou la coupe.
/// L'état se lit à trois signes qui ne reposent pas sur la seule couleur — la
/// coche, le liseré, et le dessin grisé d'un geste coupé.
///
/// ## Deux sources, comme avant
///
/// L'interrupteur principal reste à bran (`GesturesSettings`) ; tout le reste
/// pilote directement `GestureSettings.shared` de SwishClone, que le tap relit
/// à chaque geste. Un clic sur une carte s'applique au geste suivant.
struct TrackpadPane: View {
    @Bindable var model: AppModel

    /// `ObservableObject` et pas `@Observable` : SwishClone vise macOS 13.
    @ObservedObject private var tuning = GestureSettings.shared

    private var gestures: GesturesController { model.gestures }
    private var isOn: Bool { gestures.settings.isEnabled }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: LibraryPane.trackpad.title, subtitle: LibraryPane.trackpad.subtitle) {
                statusChip
            }

            Divider()

            notices

            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    TrackpadHero(isOn: isOn) { toggleMain() }

                    VStack(alignment: .leading, spacing: Space.section) {
                        ForEach(TrackpadGroup.grouped(), id: \.group) { group, entries in
                            groupSection(group, entries: entries)
                        }
                        linkedSection
                        duringSection
                    }
                    // Éteint, la page reste réglable : on choisit ses gestes
                    // avant d'allumer. Elle se lit simplement en retrait.
                    .opacity(isOn ? 1 : 0.62)
                    .branAnimation(Motion.state, value: isOn)

                    advanced
                }
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.stack)
            }
        }
    }

    // MARK: - En-tête

    private var statusChip: some View {
        HStack(spacing: Space.tight + 2) {
            Circle()
                .fill(chipColor)
                .frame(width: 7, height: 7)
            Text(chipText)
                .font(Type.meta.weight(.medium))
        }
        .padding(.horizontal, Space.small + 2)
        .padding(.vertical, Space.tight + 1)
        .background(Palette.well, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var chipColor: Color {
        guard isOn else { return Palette.asleep }
        return gestures.problem == nil ? Palette.done : Palette.attention
    }

    private var chipText: String {
        guard isOn else { return "Désactivés" }
        return gestures.problem == nil ? "Activés" : "En attente"
    }

    // MARK: - Avertissements

    @ViewBuilder
    private var notices: some View {
        if isOn, let problem = gestures.problem {
            NoticeRow(text: problem.message, symbol: "exclamationmark.triangle.fill", tint: Palette.attention) {
                switch problem {
                case .accessibilityMissing:
                    if HotkeyMonitor.isTrusted == false {
                        Button("Ouvrir les Réglages") { _ = SystemSettings.reRequestAccessibility() }
                            .controlSize(.small)
                    }
                case .anotherHost:
                    Button("Réessayer") { gestures.retry() }
                        .controlSize(.small)
                case .listeningRefused:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Les groupes de gestes

    private static let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Space.inset)]

    private func groupSection(_ group: TrackpadGroup, entries: [GestureCatalog.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Space.inset) {
            let state = TrackpadGroupState(entries, disabled: tuning.disabledActions)
            GroupHeading(title: group.title, caption: group.caption) {
                Button(state == .noneEnabled ? "Tout activer" : "Tout couper") {
                    tuning.disabledActions = TrackpadToggles.setting(
                        entries, enabled: state == .noneEnabled, in: tuning.disabledActions
                    )
                    tap()
                }
                .buttonStyle(.link)
                .font(Type.meta)
            }

            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Space.inset) {
                ForEach(entries, id: \.action) { entry in
                    GestureCard(entry: entry, isEnabled: tuning.isEnabled(entry.action)) {
                        tuning.setEnabled(entry.action, !tuning.isEnabled(entry.action))
                        tap()
                    }
                }
            }

            if group == .tap {
                centerSizeControl
            }
        }
    }

    // MARK: - Taille de la fenêtre centrée

    /// Par pas de 5 % : une valeur ronde se lit mieux qu'un 63,8 %.
    private var centerScale: Binding<Double> {
        Binding(
            get: { tuning.centerScale },
            set: { tuning.centerScale = ($0 * 20).rounded() / 20 }
        )
    }

    private var centerSizeControl: some View {
        VStack(alignment: .leading, spacing: Space.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Taille de la fenêtre centrée")
                Spacer()
                Text(tuning.centerScale.formatted(.percent.precision(.fractionLength(0))))
                    .font(Type.code)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Slider(value: centerScale, in: WindowLayout.centerScaleRange) {
                EmptyView()
            } minimumValueLabel: {
                Text("10 %").font(Type.meta).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("100 %").font(Type.meta).foregroundStyle(.secondary)
            }
            .labelsHidden()
            note("La part de l'écran que prend la fenêtre, centrée. La carte au-dessus suit le réglage.")
        }
        .padding(Space.card)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .disabled(!tuning.isEnabled(.centerReduced))
        .opacity(tuning.isEnabled(.centerReduced) ? 1 : 0.5)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Fenêtres liées

    private var linkedSection: some View {
        VStack(alignment: .leading, spacing: Space.inset) {
            GroupHeading(
                title: "Fenêtres liées",
                caption: "Deux fenêtres rangées en moitiés qui se touchent : glisser leur bord commun redimensionne les deux."
            ) { EmptyView() }

            ToggleCard(isEnabled: tuning.linkedResizeEnabled, action: {
                tuning.linkedResizeEnabled.toggle()
                tap()
            }) { isHovering in
                HStack(alignment: .center, spacing: Space.gutter) {
                    LinkedWindowsIllustration(
                        isDragged: isHovering,
                        tint: tuning.linkedResizeEnabled ? .accentColor : .secondary
                    )
                    .frame(width: 200, height: 96)
                    .branAnimation(Motion.pane, value: isHovering)

                    VStack(alignment: .leading, spacing: Space.small) {
                        CardTitle(title: "Redimensionner les fenêtres voisines", isEnabled: tuning.linkedResizeEnabled)
                        Text("Le curseur devient ↔ sur le bord commun. Échap pendant le glissé remet tout comme avant ; ⌘ enfoncé délie les deux, et seule celle au premier plan suit.")
                            .font(Type.cardBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Pendant le geste

    private var duringSection: some View {
        VStack(alignment: .leading, spacing: Space.inset) {
            GroupHeading(title: "Pendant le geste", caption: "Ce que bran montre et fait sentir avant que vous leviez les doigts.") {
                EmptyView()
            }
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Space.inset) {
                OptionCard(
                    symbol: "rectangle.inset.filled.on.rectangle",
                    title: "Aperçu",
                    detail: "Un mini-écran au centre montre où ira la fenêtre.",
                    isEnabled: tuning.previewEnabled
                ) {
                    tuning.previewEnabled.toggle()
                    tap()
                }
                OptionCard(
                    symbol: "hand.tap",
                    title: "Retour haptique",
                    detail: "Un léger clic à chaque étape validée.",
                    isEnabled: tuning.hapticsEnabled
                ) {
                    tuning.hapticsEnabled.toggle()
                    tap()
                }
            }
        }
    }

    // MARK: - Avancé

    private var advanced: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Space.stack) {
                sliderRow("Seuil du glissement", value: $tuning.swipeThreshold, in: 5 ... 50,
                          display: tuning.swipeThreshold.formatted(.number.precision(.fractionLength(0))))
                sliderRow("Seuil du pincement", value: $tuning.pinchThreshold, in: 0.02 ... 0.3,
                          display: tuning.pinchThreshold.formatted(.number.precision(.fractionLength(2))))
                note("Plus le seuil est bas, plus le geste se déclenche facilement — et plus un défilement ordinaire risque d'en devenir un.")

                sliderRow("Hauteur de la zone", value: $tuning.gestureZoneHeight, in: 20 ... 100,
                          display: tuning.gestureZoneHeight.formatted(.number.precision(.fractionLength(0))) + " pt")
                sliderRow("Durée de l'animation", value: $tuning.animationDuration, in: 0.05 ... 0.5,
                          display: tuning.animationDuration.formatted(.number.precision(.fractionLength(2))) + " s")

                sliderRow("Pause entre deux étapes", value: $tuning.stepPause, in: 0.15 ... 0.5,
                          display: tuning.stepPause.formatted(.number.precision(.fractionLength(2))) + " s")
                sliderRow("Délai d'annulation", value: $tuning.cancelTimeout, in: 0.6 ... 2,
                          display: tuning.cancelTimeout.formatted(.number.precision(.fractionLength(1))) + " s")
                note("Immobile plus longtemps que la pause, une direction est validée et on peut en enchaîner une autre sans lever les doigts. Immobile plus longtemps que le délai d'annulation, le geste est abandonné et rien n'est appliqué.")
            }
            .padding(.top, Space.inset)
        } label: {
            Text("Avancé")
                .font(Type.groupHead)
        }
        .padding(Space.card)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Les bornes sont celles de la fenêtre de préférences de SwishClone :
    /// choisies là-bas, sur le trackpad.
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Type.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func toggleMain() {
        gestures.setEnabled(!isOn)
        tap()
    }

    /// Un clic ressenti, comme un geste validé — seulement si le retour
    /// haptique est voulu.
    private func tap() {
        guard tuning.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

// MARK: - La bannière d'activation

/// **L'entrée de la page** : un geste qui se rejoue en boucle, et le seul
/// bouton qui allume ou éteint tout.
private struct TrackpadHero: View {
    let isOn: Bool
    let toggle: () -> Void

    /// Les gestes que la bannière fait défiler : les plus courants d'abord.
    private static let reel: [GestureAction] = [.leftHalf, .rightHalf, .maximize, .bottomRightQuarter, .toggleFullScreen]
    private static let beat: TimeInterval = 2.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: Space.gutter) {
            TimelineView(.periodic(from: .now, by: Self.beat / 2)) { context in
                let tick = reduceMotion ? 1 : Int(context.date.timeIntervalSinceReferenceDate / (Self.beat / 2))
                let action = Self.reel[(tick / 2) % Self.reel.count]
                VStack(spacing: Space.small) {
                    GestureMiniScreen(action: action, isDone: tick % 2 == 1, showsFingers: !reduceMotion,
                                      tint: isOn ? .accentColor : .secondary)
                        .frame(width: 220)
                        .branAnimation(Motion.pane, value: tick)
                    Text("\(GestureCatalog.entry(for: action)?.triggers[0].symbols ?? "") · \(action.label())")
                        .font(Type.meta.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: Space.inset) {
                Text("Ranger ses fenêtres du bout de deux doigts")
                    .font(Type.sheetTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Deux doigts sur la barre de titre d'une fenêtre, même en arrière-plan : glisser la range, pincer la met en plein écran ou la ferme. L'action part quand vous levez les doigts ; Échap annule. Ailleurs, le trackpad ne change pas.")
                    .font(Type.paneLead)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                activation
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.gutter)
        .background {
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.panel)
                .overlay {
                    // La même lueur que le cadran de « Débit » : faible, et
                    // seulement quand c'est allumé.
                    RadialGradient(colors: [Color.accentColor.opacity(0.16), .clear],
                                   center: .leading, startRadius: 0, endRadius: 320)
                        .opacity(isOn ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        }
        .branAnimation(Motion.state, value: isOn)
    }

    @ViewBuilder
    private var activation: some View {
        if isOn {
            HStack(spacing: Space.inset) {
                Label("Gestes activés", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.done)
                    .font(Type.cardBodyStrong)
                Button("Désactiver", action: toggle)
                    .controlSize(.large)
            }
        } else {
            Button(action: toggle) {
                Label("Activer les gestes", systemImage: "hand.draw")
                    .padding(.horizontal, Space.small)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Les cartes

/// Le titre d'un groupe, sa phrase d'explication, et une action à droite.
private struct GroupHeading<Trailing: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .font(Type.groupHead)
                Text(caption)
                    .font(Type.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.stack)
            trailing()
        }
        .accessibilityElement(children: .contain)
    }
}

/// Le nom d'une carte et sa coche.
private struct CardTitle: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.small) {
            Text(title)
                .font(Type.cardTitle)
                .lineLimit(2)
            Spacer(minLength: 0)
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

/// **Une carte qui est son propre interrupteur.** Fond de carte, liseré
/// d'accent quand elle est active, et le survol transmis au contenu pour
/// qu'il puisse rejouer son geste.
private struct ToggleCard<Content: View>: View {
    let isEnabled: Bool
    let action: () -> Void
    @ViewBuilder var content: (_ isHovering: Bool) -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content(isHovering)
                .padding(Space.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Palette.card(hover: isHovering))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(isEnabled ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator),
                                      lineWidth: isEnabled ? 1.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .branAnimation(Motion.hover, value: isHovering)
        .branAnimation(Motion.state, value: isEnabled)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isEnabled ? "Activé" : "Coupé")
    }
}

/// Un geste : son dessin, son nom, et ce que font les doigts.
private struct GestureCard: View {
    let entry: GestureCatalog.Entry
    let isEnabled: Bool
    let toggle: () -> Void

    /// Faux le temps de repartir du début, au survol.
    @State private var isDone = true
    @State private var replay: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToggleCard(isEnabled: isEnabled, action: toggle) { isHovering in
            VStack(alignment: .leading, spacing: Space.small) {
                GestureMiniScreen(
                    action: entry.action,
                    isDone: isDone,
                    showsFingers: isHovering && !reduceMotion,
                    tint: isEnabled ? .accentColor : .secondary
                )
                .saturation(isEnabled ? 1 : 0)
                .opacity(isEnabled ? 1 : 0.6)

                CardTitle(title: entry.action.label(), isEnabled: isEnabled)

                Text(entry.triggers[0].symbols)
                    .font(Type.code)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: isHovering) { _, hovering in
                if hovering { play() }
            }
        }
        .accessibilityLabel("\(entry.action.label()), \(entry.triggers[0].symbols)")
    }

    /// Rejoue le geste : la fenêtre repart de sa place, puis y retourne.
    private func play() {
        guard reduceMotion == false else { return }
        replay?.cancel()
        isDone = false
        replay = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard Task.isCancelled == false else { return }
            withAnimation(Motion.pane) { isDone = true }
        }
    }
}

/// Un réglage « pendant le geste » : un grand symbole plutôt qu'un dessin.
private struct OptionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        ToggleCard(isEnabled: isEnabled, action: toggle) { _ in
            VStack(alignment: .leading, spacing: Space.small) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(height: 34)
                CardTitle(title: title, isEnabled: isEnabled)
                Text(detail)
                    .font(Type.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(title)
    }
}
