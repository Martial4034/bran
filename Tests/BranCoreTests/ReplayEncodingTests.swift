import Testing
@testable import BranCore

@Suite("ReplayEncoding")
struct ReplayEncodingTests {

    @Test("Le closing du 08/10 : 5160×2160 devient 2580×1080 à 600 kbit/s")
    func ultrawideCapture() {
        let encoding = ReplayEncoding(sourceWidth: 5160, sourceHeight: 2160, frameRate: 30)

        #expect(encoding.width == 2580)
        #expect(encoding.height == 1080)
        #expect(encoding.bitrate == 600_000)
    }

    @Test("Une source plus basse que 1080 lignes n'est jamais agrandie")
    func neverUpscales() {
        let encoding = ReplayEncoding(sourceWidth: 1280, sourceHeight: 800, frameRate: 30)

        #expect(encoding.width == 1280)
        #expect(encoding.height == 800)
        #expect(encoding.bitrate < 600_000)
    }

    @Test("Les dimensions restent paires, quel que soit le rapport")
    func evenDimensions() {
        // 3456×2234 (MacBook Pro 16" en Retina) : 2234 → 1080, largeur 1670,8.
        let encoding = ReplayEncoding(sourceWidth: 3456, sourceHeight: 2234, frameRate: 30)

        #expect(encoding.height == 1080)
        #expect(encoding.width.isMultiple(of: 2))
        #expect(encoding.width == 1672)
    }

    @Test("Le débit suit les pixels, avec un plancher")
    func bitrateFloor() {
        let tiny = ReplayEncoding(sourceWidth: 320, sourceHeight: 200, frameRate: 30)
        #expect(tiny.bitrate == ReplayEncoding.minimumBitrate)
    }

    @Test("Une cadence inconnue compte pour 30 images/s")
    func unknownFrameRate() {
        let unknown = ReplayEncoding(sourceWidth: 5160, sourceHeight: 2160, frameRate: 0)
        let thirty = ReplayEncoding(sourceWidth: 5160, sourceHeight: 2160, frameRate: 30)
        #expect(unknown == thirty)
    }

    @Test("Une source dégénérée ne produit pas de dimension nulle")
    func degenerateSource() {
        let encoding = ReplayEncoding(sourceWidth: 0, sourceHeight: 0, frameRate: 30)
        #expect(encoding.width >= 2)
        #expect(encoding.height >= 2)
    }
}
