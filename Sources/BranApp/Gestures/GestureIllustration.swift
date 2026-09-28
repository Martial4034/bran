import SwiftUI
import SwishCloneCore

/// **Le mini-écran d'une carte de geste** : ce que fait le geste, dessiné.
///
/// ```
/// ┌──────────────────────────────┐  ← barre de menus
/// │┌────────────┐                │
/// ││● ● ●  ·· → │   ┌ ─ ─ ─ ┐    │  ← la fenêtre part de sa place (pointillés)
/// ││            │                │    et va sur la zone du geste (accent) ;
/// ││            │   └ ─ ─ ─ ┘    │    deux points rejouent les doigts
/// │└────────────┘                │
/// │        ╭──────────╮          │  ← le Dock
/// └────────╰──────────╯──────────┘
/// ```
///
/// **Pas d'image, pas de vidéo** : des formes, dans un repère fixe de
/// 160 × 100 mis à l'échelle. La zone d'arrivée vient de
/// `WindowLayout.frame(for:in:)` — la même fonction qui place les vraies
/// fenêtres. Le dessin ne peut donc pas promettre une moitié que le geste ne
/// donnerait pas.
///
/// Au repos, la carte montre le résultat ; au survol, elle **rejoue** le geste
/// (la fenêtre repart de sa place, les doigts glissent), comme les aperçus des
/// Réglages système › Trackpad.
struct GestureMiniScreen: View {
    let action: GestureAction
    /// Faux : la fenêtre est à sa place de départ. Vrai : le geste est fait.
    let isDone: Bool
    /// Les doigts ne se montrent que pendant la relecture.
    let showsFingers: Bool
    let tint: Color

    /// Le repère du dessin, et ses repères fixes.
    enum Metric {
        static let screen = CGSize(width: 160, height: 100)
        static let menuBar: CGFloat = 6
        static let dockHeight: CGFloat = 9
        static let dockWidth: CGFloat = 64
        static let visible = CGRect(x: 0, y: menuBar, width: 160, height: 100 - menuBar - dockHeight - 3)
        static let start = CGRect(x: 44, y: 24, width: 72, height: 46)
        static let dockIcons = 5
        /// L'icône du Dock que « réduire » et « quitter » visent.
        static let dockTarget = 3
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Metric.screen.width
            ZStack(alignment: .topLeading) {
                // L'écran.
                RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                    .fill(.background.secondary)
                RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                    .strokeBorder(.separator)

                // La barre de menus.
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: proxy.size.width, height: Metric.menuBar * scale)
                    .opacity(hidesChrome ? 0 : 1)

                dock(scale: scale)
                    .opacity(hidesChrome ? 0 : 1)

                // D'où part la fenêtre, pour que le mouvement se lise même
                // figé.
                if showsGhost {
                    RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(.tertiary)
                        .frame(width: Metric.start.width * scale, height: Metric.start.height * scale)
                        .offset(x: Metric.start.minX * scale, y: Metric.start.minY * scale)
                }

                window(scale: scale)

                if showsFingers {
                    fingers(scale: scale)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
        }
        .aspectRatio(Metric.screen.width / Metric.screen.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - La fenêtre

    private var target: CGRect {
        switch action {
        case .minimize:
            let icon = Self.dockIconFrame(Metric.dockTarget)
            return CGRect(x: icon.midX - 5, y: icon.minY, width: 10, height: 6)
        case .toggleFullScreen:
            return CGRect(origin: .zero, size: Metric.screen)
        case .close, .quitApp, .centerReduced:
            return Metric.start
        default:
            return WindowLayout.frame(for: action, in: Metric.visible) ?? Metric.start
        }
    }

    private var frame: CGRect { isDone ? target : Metric.start }

    /// Fermer et quitter font disparaître la fenêtre, sur place.
    private var vanishes: Bool { isDone && (action == .close || action == .quitApp) }

    private var hidesChrome: Bool { isDone && action == .toggleFullScreen }

    private var showsGhost: Bool {
        switch action {
        case .close, .quitApp, .toggleFullScreen, .minimize: false
        default: isDone
        }
    }

    private func window(scale: CGFloat) -> some View {
        let rect = frame
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                .fill(tint.opacity(isDone ? 0.28 : 0.14))
            RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                .strokeBorder(tint.opacity(0.9), lineWidth: 1)
            // La barre de titre et ses trois feux : c'est là que le geste se
            // fait, donc c'est ce qui doit se reconnaître.
            HStack(spacing: 1.6 * scale) {
                ForEach(0 ..< 3) { index in
                    Circle()
                        .fill(lightColor(index))
                        .frame(width: 2.6 * scale, height: 2.6 * scale)
                }
            }
            .padding(.leading, 3 * scale)
            .padding(.top, 2.5 * scale)
            .opacity(rect.height > 12 ? 1 : 0)
        }
        .frame(width: rect.width * scale, height: rect.height * scale)
        .scaleEffect(vanishes ? 0.82 : 1)
        .opacity(vanishes ? 0 : 1)
        .offset(x: rect.minX * scale, y: rect.minY * scale)
    }

    /// Le feu du geste s'allume : rouge pour fermer, vert pour le plein écran,
    /// jaune pour réduire. Les autres restent neutres.
    private func lightColor(_ index: Int) -> Color {
        let lit: Int? = switch action {
        case .close, .quitApp: 0
        case .minimize: 1
        case .toggleFullScreen: 2
        default: nil
        }
        guard index == lit else { return Color.secondary.opacity(0.45) }
        return [Color.red, .yellow, .green][index]
    }

    // MARK: - Le Dock

    static func dockIconFrame(_ index: Int) -> CGRect {
        let size: CGFloat = 7
        let gap: CGFloat = 3.5
        let total = CGFloat(Metric.dockIcons) * size + CGFloat(Metric.dockIcons - 1) * gap
        let x = (Metric.screen.width - total) / 2 + CGFloat(index) * (size + gap)
        return CGRect(x: x, y: Metric.screen.height - Metric.dockHeight - 1, width: size, height: size)
    }

    private func dock(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            let width = Metric.dockWidth
            RoundedRectangle(cornerRadius: 3.5 * scale, style: .continuous)
                .fill(.quaternary)
                .frame(width: width * scale, height: (Metric.dockHeight + 2) * scale)
                .offset(x: (Metric.screen.width - width) / 2 * scale,
                        y: (Metric.screen.height - Metric.dockHeight - 3) * scale)
            ForEach(0 ..< Metric.dockIcons, id: \.self) { index in
                let icon = Self.dockIconFrame(index)
                let isTarget = index == Metric.dockTarget && (action == .quitApp || action == .minimize)
                RoundedRectangle(cornerRadius: 1.8 * scale, style: .continuous)
                    .fill(isTarget ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                    .frame(width: icon.width * scale, height: icon.height * scale)
                    .scaleEffect(isTarget && action == .quitApp && isDone ? 0.55 : 1)
                    .opacity(isTarget && action == .quitApp && isDone ? 0.35 : 1)
                    .offset(x: icon.minX * scale, y: icon.minY * scale)
            }
        }
    }

    // MARK: - Les doigts

    /// Deux points côte à côte, posés là où le geste se fait (la barre de
    /// titre, ou l'icône du Dock), qui glissent dans le sens du geste ou
    /// s'écartent et se resserrent.
    private func fingers(scale: CGFloat) -> some View {
        let anchor = fingerAnchor
        let (first, second) = fingerOffsets
        let dot = 5.5 * scale
        return ZStack(alignment: .topLeading) {
            ForEach(Array([first, second].enumerated()), id: \.offset) { _, offset in
                Circle()
                    .fill(.primary.opacity(0.55))
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                    .frame(width: dot, height: dot)
                    .offset(x: (anchor.x + offset.width) * scale - dot / 2,
                            y: (anchor.y + offset.height) * scale - dot / 2)
            }
        }
    }

    private var fingerAnchor: CGPoint {
        if action == .quitApp {
            let icon = Self.dockIconFrame(Metric.dockTarget)
            return CGPoint(x: icon.midX, y: icon.midY - 6)
        }
        // Le milieu de la barre de titre de la fenêtre au départ : les doigts
        // restent là où le geste a commencé, la fenêtre part sous eux.
        return CGPoint(x: Metric.start.midX, y: Metric.start.minY + 4)
    }

    /// Le décalage de chaque doigt, geste fait. Au départ, les deux sont
    /// côte à côte, à 4 points l'un de l'autre.
    private var fingerOffsets: (CGSize, CGSize) {
        let spread: CGFloat = 4
        guard isDone else {
            // Un pincement qui ferme part écarté.
            let start: CGFloat = (action == .close || action == .quitApp) ? 9 : spread
            return (CGSize(width: -start, height: 0), CGSize(width: start, height: 0))
        }
        switch action {
        case .toggleFullScreen:
            return (CGSize(width: -12, height: 0), CGSize(width: 12, height: 0))
        case .close, .quitApp:
            return (CGSize(width: -2.5, height: 0), CGSize(width: 2.5, height: 0))
        default:
            let travel = swipeTravel
            return (CGSize(width: -spread + travel.width, height: travel.height),
                    CGSize(width: spread + travel.width, height: travel.height))
        }
    }

    /// Où les doigts ont glissé : la somme des étapes du déclencheur. Une
    /// diagonale compte ses deux composantes, en un seul trait.
    private var swipeTravel: CGSize {
        guard let entry = GestureCatalog.entry(for: action),
              case let .swipes(steps) = entry.triggers[0] else { return .zero }
        let step: CGFloat = 13
        return steps.reduce(.zero) { sum, direction in
            let dx: CGFloat = switch direction.horizontal {
            case .left?: -step
            case .right?: step
            default: 0
            }
            let dy: CGFloat = switch direction.vertical {
            case .up?: -step * 0.7
            case .down?: step * 0.7
            default: 0
            }
            return CGSize(width: sum.width + dx, height: sum.height + dy)
        }
    }
}

/// **Deux fenêtres liées**, et leur bord commun qui se déplace.
struct LinkedWindowsIllustration: View {
    /// 0 : partage à 50 %. 1 : bord commun glissé vers la droite.
    let isDragged: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let border = size.width * (isDragged ? 0.64 : 0.5)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.background.secondary)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator)
                pane(width: border - 6, tint: tint)
                    .offset(x: 4, y: 4)
                pane(width: size.width - border - 6, tint: tint)
                    .offset(x: border + 2, y: 4)
                // La poignée : une barre d'accent et le curseur ↔.
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: size.height * 0.34)
                    .offset(x: border - 1.5, y: size.height * 0.33)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(3)
                    .background(.background, in: Capsule())
                    .offset(x: border - 11, y: size.height * 0.5 + 12)
            }
            .frame(height: size.height)
        }
        .accessibilityHidden(true)
    }

    private func pane(width: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(tint.opacity(0.8)))
            .frame(width: max(width, 0))
            .padding(.bottom, 8)
    }
}
