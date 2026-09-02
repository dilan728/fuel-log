import SwiftUI

/// The complete colour vocabulary of Plate.
///
/// Nothing outside this file names a literal colour. The palette is deliberately tiny:
/// warm paper, one ink, one ember. Two rules that were learned the hard way:
///
/// * **The page ground is flat.** The first version washed the background with a
///   time-of-day gradient; measured, it contained 586 distinct colours in the margins
///   alone, swinging 40 levels. Nothing looks more generated than a page that cannot
///   decide what colour it is.
/// * **Tints are opaque, not alpha.** Ember at 26% over a near-white ground has almost
///   no contrast at small sizes. Every tint here is pre-blended toward the ground.
enum Palette {

    // MARK: Ground

    /// The page. One flat colour, edge to edge.
    static let paper = dynamic(light: 0xFAF7F2, dark: 0x0C0B0A)

    /// A surface *below* the page — the well an image sits in before it loads.
    static let paperSunken = dynamic(light: 0xF0EAE1, dark: 0x171513)

    /// A surface above the page. Used only by the composer, which genuinely floats.
    static let paperRaised = dynamic(light: 0xFFFFFF, dark: 0x1A1816)

    // MARK: Ink

    private static let inkBase = dynamic(light: 0x14120F, dark: 0xF6F2EB)

    static let ink = inkBase
    static let inkSoft = inkBase.opacity(0.60)
    static let inkFaint = inkBase.opacity(0.38)
    static let inkGhost = inkBase.opacity(0.13)

    /// One-pixel rules. Deliberately lighter than a system separator: at one physical
    /// pixel a stronger value reads as a drawn line rather than as structure.
    static let hairline = dynamic(light: 0x14120F, dark: 0xF6F2EB).opacity(0.13)

    // MARK: Accent

    static let ember = dynamic(light: 0xC8451F, dark: 0xFF6B3D)

    /// Ember pre-blended toward paper, for fills that carry text.
    static let emberWash = dynamic(light: 0xF7E7E0, dark: 0x2A1710)

    /// Ember for text on `emberWash`.
    static let emberInk = dynamic(light: 0x9E3617, dark: 0xFF8A63)

    // MARK: Macro densities
    //
    // Same hue, three opaque densities. Reads as one family at a glance and holds its
    // weight at a 2pt rule, which an alpha tint does not.

    static let protein = ember
    static let carbs = dynamic(light: 0xDE8E76, dark: 0x9E4A2A)
    static let fat = dynamic(light: 0xEFC7B8, dark: 0x5E2E1C)

    /// The unfilled remainder of a measure.
    static let track = dynamic(light: 0x14120F, dark: 0xF6F2EB).opacity(0.09)

    // MARK: Semantic

    /// Only for genuine problems — a failed request. Never for "over budget".
    static let alert = dynamic(light: 0xA33418, dark: 0xFF7A5C)

    // MARK: Construction

    /// Builds a `Color` that resolves per trait collection, so light and dark are both
    /// correct inside shader-backed and rasterised views.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

// MARK: - UIColor helpers

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Linear blend toward `other`. `amount == 0` returns self.
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        let t = min(max(amount, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
