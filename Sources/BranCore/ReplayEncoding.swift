import Foundation

/// La définition et le débit de la vidéo qu'on garde d'une réunion.
///
/// **Une vidéo de relecture, pas une archive de l'écran.** La fusion gardait la
/// pleine définition capturée — 5160×2160 à environ 10 Mbit/s : 1,8 Go pour le
/// closing de 30 min du 08/10/2026 —, alors que ces fichiers partent sur un
/// Drive où personne ne les regardera peut-être jamais. Ce qu'on doit pouvoir
/// en faire, c'est relire un échange et lire une slide partagée.
///
/// Mesuré le 08/10/2026 sur 2 min de ce closing (`bran-spike shrink`),
/// extrapolé à 30 min :
///
/// ```
///   5160×2160  ~10 Mbit/s   1,8 Go    2,4× le temps réel   (avant)
///   2580×1080  1,5 Mbit/s   361 Mo    7,5×
///   2580×1080    1 Mbit/s   249 Mo    7,6×
///   2580×1080  600 kbit/s   179 Mo    7,6×                 ← retenu
///   1720×720   500 kbit/s   135 Mo    7,7×
/// ```
///
/// À 1080 lignes et 600 kbit/s, un tableau de slide en corps 11 se lit sans
/// effort ; en 720 lignes, les petites polices d'un écran ultra-large
/// deviennent limites pour 44 Mo de gagnés seulement. Et la fusion va trois
/// fois plus vite, puisque l'encodeur n'a plus que le quart des pixels.
///
/// Pur calcul, dans `BranCore`, pour se tester sans vidéo.
public struct ReplayEncoding: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bitrate: Int

    /// Plafond de hauteur. Une source plus basse n'est jamais agrandie.
    public static let maxHeight = 1080

    /// Le débit retenu pour 2580×1080 à 30 images/s, ramené au pixel pour
    /// qu'une source plus petite — un écran 16:10, un réglage « Standard » —
    /// reçoive un débit proportionnel au lieu des mêmes 600 kbit/s.
    public static let bitsPerPixelPerFrame = 600_000.0 / (2580.0 * 1080.0 * 30.0)

    /// Plancher : en dessous, même une fenêtre de visio en vignette se défait.
    public static let minimumBitrate = 150_000

    public init(sourceWidth: Double, sourceHeight: Double, frameRate: Double) {
        let safeHeight = max(sourceHeight, 2)
        let safeWidth = max(sourceWidth, 2)
        let targetHeight = min(Self.maxHeight, Int(safeHeight.rounded()))
        let scale = Double(targetHeight) / safeHeight

        height = Self.even(Double(targetHeight))
        width = Self.even(safeWidth * scale)

        let rate = frameRate > 1 ? frameRate : 30
        let computed = Double(width) * Double(height) * rate * Self.bitsPerPixelPerFrame
        bitrate = max(Self.minimumBitrate, Int(computed.rounded()))
    }

    /// HEVC exige des dimensions paires.
    private static func even(_ value: Double) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}
