import SwishCloneCore

/// **Les groupes de la page « Trackpad »**, dans l'ordre où on les lit.
///
/// Ce n'est pas une table recopiée geste par geste : chaque entrée du
/// catalogue de SwishClone est rangée **par une règle** (sa cible, sa famille,
/// sa forme). Un geste ajouté un jour au catalogue trouve donc sa place tout
/// seul, et le test qui vérifie que chaque geste apparaît une fois le rattrape
/// si la règle ne suffit plus.
public enum TrackpadGroup: String, CaseIterable, Sendable {
    /// Un seul glissé, ou deux fois le même : moitiés, remplir, réduire.
    case titlebar
    /// Les quarts : une diagonale d'un seul geste, ou deux directions
    /// enchaînées avec une pause.
    case quarters
    /// Écarter et resserrer sur une barre de titre.
    case pinch
    /// Sur une icône du Dock.
    case dock

    public var title: String {
        switch self {
        case .titlebar: "Glisser sur la barre de titre"
        case .quarters: "Glisser en diagonale"
        case .pinch: "Pincer"
        case .dock: "Sur une icône du Dock"
        }
    }

    public var caption: String {
        switch self {
        case .titlebar: "Deux doigts sur la barre de titre d'une fenêtre, même en arrière-plan."
        case .quarters: "D'un seul geste, pour un quart d'écran. Ou deux directions, avec une courte pause entre les deux, sans lever les doigts."
        case .pinch: "Écarter ou resserrer deux doigts sur la barre de titre."
        case .dock: "Resserrer sur l'icône d'une app lancée. Ni le Finder ni bran ne sont jamais quittés."
        }
    }

    public static func of(_ entry: GestureCatalog.Entry) -> TrackpadGroup {
        if entry.target == .dockApp { return .dock }
        if entry.family == .pinch { return .pinch }
        if case let .swipes(steps) = entry.triggers[0],
           steps.contains(where: \.isDiagonal) || Set(steps).count > 1 { return .quarters }
        return .titlebar
    }

    /// Les groupes non vides, chacun avec ses gestes dans l'ordre du catalogue.
    public static func grouped(
        _ entries: [GestureCatalog.Entry] = GestureCatalog.entries
    ) -> [(group: TrackpadGroup, entries: [GestureCatalog.Entry])] {
        allCases.compactMap { group in
            let members = entries.filter { of($0) == group }
            return members.isEmpty ? nil : (group, members)
        }
    }
}

/// L'état d'un groupe, pour son bouton « tout activer » ou « tout couper ».
public enum TrackpadGroupState: Equatable, Sendable {
    case allEnabled, someEnabled, noneEnabled

    public init(_ entries: [GestureCatalog.Entry], disabled: Set<GestureAction>) {
        let off = entries.filter { disabled.contains($0.action) }.count
        switch off {
        case 0: self = .allEnabled
        case entries.count: self = .noneEnabled
        default: self = .someEnabled
        }
    }
}

public enum TrackpadToggles {

    /// Tout un groupe allumé ou coupé, sans toucher aux autres gestes.
    public static func setting(
        _ entries: [GestureCatalog.Entry],
        enabled: Bool,
        in disabled: Set<GestureAction>
    ) -> Set<GestureAction> {
        let actions = Set(entries.map(\.action))
        return enabled ? disabled.subtracting(actions) : disabled.union(actions)
    }

    /// **La reprise des deux anciens interrupteurs, « glisser » et « pincer ».**
    ///
    /// La page n'en a plus : chaque geste a sa carte. Mais quelqu'un qui avait
    /// coupé « pincer » dans l'ancienne section verrait sinon des cartes
    /// allumées qui ne marchent pas. On coupe donc, une fois, chaque geste de
    /// la famille éteinte, puis on rallume l'interrupteur de famille : la
    /// liste des gestes coupés devient la seule source.
    ///
    /// `nil` quand il n'y a rien à reprendre.
    public static func migrated(
        swipeEnabled: Bool,
        pinchEnabled: Bool,
        disabled: Set<GestureAction>,
        entries: [GestureCatalog.Entry] = GestureCatalog.entries
    ) -> Set<GestureAction>? {
        guard swipeEnabled == false || pinchEnabled == false else { return nil }
        var result = disabled
        for entry in entries {
            if entry.family == .swipe, swipeEnabled == false { result.insert(entry.action) }
            if entry.family == .pinch, pinchEnabled == false { result.insert(entry.action) }
        }
        return result
    }
}
