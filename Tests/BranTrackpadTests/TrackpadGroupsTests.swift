import Testing
import SwishCloneCore
@testable import BranTrackpad

/// La page ne recopie pas la table des gestes : elle range le catalogue de
/// SwishClone par règle. Ces tests vérifient que la règle ne perd ni ne double
/// aucun geste, et que les boutons de groupe ne débordent pas sur les autres.
@Suite("Les groupes de la page Trackpad")
struct TrackpadGroupsTests {

    @Test("Chaque geste du catalogue apparaît une fois, et une seule")
    func everyGestureOnce() {
        let shown = TrackpadGroup.grouped().flatMap { $0.entries.map(\.action) }
        #expect(shown.count == GestureCatalog.entries.count)
        #expect(Set(shown) == Set(GestureCatalog.entries.map(\.action)))
    }

    @Test("Les groupes, dans l'ordre de lecture")
    func groups() {
        let groups = TrackpadGroup.grouped()
        #expect(groups.map(\.group) == [.titlebar, .quarters, .pinch, .dock])
        let byGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.group, Set($0.entries.map(\.action))) })
        #expect(byGroup[.titlebar] == [.leftHalf, .rightHalf, .maximize, .minimize, .topHalf, .bottomHalf])
        #expect(byGroup[.quarters] == [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter])
        #expect(byGroup[.pinch] == [.toggleFullScreen, .close])
        #expect(byGroup[.dock] == [.quitApp])
    }

    @Test("↑↑ reste avec les glissés simples, ↓ puis → va dans les quarts")
    func doubleSwipeIsNotAQuarter() {
        #expect(TrackpadGroup.of(GestureCatalog.entry(for: .topHalf)!) == .titlebar)
        #expect(TrackpadGroup.of(GestureCatalog.entry(for: .bottomRightQuarter)!) == .quarters)
    }

    @Test("Un groupe vide n'est pas affiché")
    func emptyGroupHidden() {
        let entries = GestureCatalog.entries.filter { $0.target == .titlebar }
        #expect(TrackpadGroup.grouped(entries).map(\.group) == [.titlebar, .quarters, .pinch])
    }

    // MARK: - État et bouton d'un groupe

    @Test("L'état d'un groupe : tout, une partie, rien")
    func groupState() {
        let pinch = GestureCatalog.entries.filter { TrackpadGroup.of($0) == .pinch }
        #expect(TrackpadGroupState(pinch, disabled: []) == .allEnabled)
        #expect(TrackpadGroupState(pinch, disabled: [.close, .minimize]) == .someEnabled)
        #expect(TrackpadGroupState(pinch, disabled: [.close, .toggleFullScreen]) == .noneEnabled)
    }

    @Test("Couper un groupe ne touche pas aux autres gestes")
    func groupToggle() {
        let pinch = GestureCatalog.entries.filter { TrackpadGroup.of($0) == .pinch }
        let off = TrackpadToggles.setting(pinch, enabled: false, in: [.minimize])
        #expect(off == [.minimize, .close, .toggleFullScreen])
        let on = TrackpadToggles.setting(pinch, enabled: true, in: off)
        #expect(on == [.minimize], "« réduire », coupé à part, le reste")
    }

    // MARK: - Reprise des anciens interrupteurs

    @Test("Rien à reprendre quand les deux familles sont allumées")
    func noMigration() {
        #expect(TrackpadToggles.migrated(swipeEnabled: true, pinchEnabled: true, disabled: [.close]) == nil)
    }

    @Test("« Pincer » éteint : chaque pincement est coupé, y compris sur le Dock")
    func pinchMigration() {
        let result = TrackpadToggles.migrated(swipeEnabled: true, pinchEnabled: false, disabled: [.minimize])
        #expect(result == [.minimize, .toggleFullScreen, .close, .quitApp])
    }

    @Test("« Glisser » éteint : chaque glissé est coupé, quarts compris")
    func swipeMigration() {
        let result = TrackpadToggles.migrated(swipeEnabled: false, pinchEnabled: true, disabled: [])
        let swipes = Set(GestureCatalog.entries.filter { $0.family == .swipe }.map(\.action))
        #expect(result == swipes)
        #expect(swipes.count == 10)
    }
}
