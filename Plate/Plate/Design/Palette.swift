import SwiftUI

/// The complete color vocabulary of Plate.
///
/// Nothing outside this file is allowed to name a literal color. The palette is
/// deliberately tiny: warm paper, one ink, one ember. Macros are separated by
/// *density* of the same ember rather than by hue — a screen full of food
/// photography already has plenty of color, and traffic-light macro chips would
/// turn it into a christmas tree.
enum Palette {

    // MARK: Ground

    /// App background. Warm off-white in light, near-black with a warm bias in dark.
    static let paper = dynamic(light: 0xFBF8F4, dark: 0x0D0C0B)

    /// Cards, bubbles, anything lifted off `paper`.
    static let paperRaised = dynamic(light: 0xFFFFFF, dark: 0x171614)

    /// One step further up — used for the composer and floating bars.
    static let paperFloating = dynamic(light: 0xFFFFFF, dark: 0x1F1D1B)

    // MARK: Ink

    private static let inkBase = dynamic(light: 0x171511, dark: 0xF5F1EA)

    static let ink = inkBase
    static let inkSoft = inkBase.opacity(0.62)
    static let inkFaint = inkBase.opacity(0.34)
    static let inkGhost = inkBase.opacity(0.16)

    /// 0.5pt separators. Deliberately weaker than a system separator.
    static let hairline = dynamic(light: 0x171511, dark: 0xF5F1EA).opacity(0.09)

    // MARK: Accent

    /// The single accent. Everything interactive, everything "yours".
    static let ember = dynamic(light: 0xE2542B, dark: 0xFF6B3D)

    /// Ember at chip/fill strength.
    static let emberSoft = dynamic(light: 0xE2542B, dark: 0xFF6B3D).opacity(0.13)

    /// Ember for text on `emberSoft`.
    static let emberInk = dynamic(light: 0xB43D1B, dark: 0xFF8A63)

    // MARK: Macro densities
    //
    // Same hue, three densities. Reads as one family at a glance and stays legible
    // at ring stroke widths of 6pt.

    // Opaque tints, not alpha. Ember at 26% opacity over the near-white ring track has
    // almost no contrast, so a lightly-filled ring read as three disconnected ticks
    // rather than one short arc. These are the same colours pre-blended toward the
    // ground, so they hold their weight over any background.
    static let protein = ember
    static let carbs = dynamic(light: 0xED9E85, dark: 0x9E4A2A)
    static let fat = dynamic(light: 0xF4CABC, dark: 0x5E2E1C)

    /// Unfilled remainder of the ring.
    static let ringTrack = dynamic(light: 0x171511, dark: 0xF5F1EA).opacity(0.07)

    // MARK: Semantic

    /// Used only for genuine problems (a failed request), never for "over budget".
    static let alert = dynamic(light: 0xB4381F, dark: 0xFF7A5C)

    // MARK: - Time-of-day ground
    //
    // The app background carries a very low-amplitude wash that tracks the hour.
    // It is never announced; it just means 7am and 9pm don't feel identical.

    /// Two stops for the background gradient at a given hour (0..<24).
    static func groundWash(hour: Int) -> (top: Color, bottom: Color) {
        let h = Double((hour % 24 + 24) % 24)
        // Warm at dawn/dusk, neutral-cool at midday, deep at night.
        let warmth = cos((h - 7.5) / 24 * 2 * .pi)          // peaks at 07:30
        let dusk = cos((h - 19.0) / 24 * 2 * .pi)           // peaks at 19:00
        let amber = max(0, warmth) * 0.5 + max(0, dusk) * 0.7
        let cool = max(0, cos((h - 13.0) / 24 * 2 * .pi))

        let top = dynamicBlend(
            light: (0xFFF3E6, 0xEEF2F6, amber, cool),
            dark: (0x1A120C, 0x0B1016, amber, cool)
        )
        return (top, paper)
    }

    // MARK: - Construction

    /// Builds a `Color` that resolves per trait collection, so light/dark are
    /// correct even inside `drawingGroup()` and shader-backed views.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// Blends two hexes toward `paper` by the given weights, per appearance.
    private static func dynamicBlend(
        light: (UInt32, UInt32, Double, Double),
        dark: (UInt32, UInt32, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let spec = isDark ? dark : light
            let base = UIColor(hex: isDark ? 0x0D0C0B : 0xFBF8F4)
            let warm = UIColor(hex: spec.0).blended(with: base, amount: 1 - spec.2 * 0.9)
            return warm.blended(with: UIColor(hex: spec.1), amount: spec.3 * 0.35)
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
