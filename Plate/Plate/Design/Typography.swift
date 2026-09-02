import SwiftUI

/// Plate's type scale.
///
/// Serif for anything that is *content* — food names, calorie counts, day headers.
/// Sans for anything that is *chrome* — labels, buttons, captions. That single
/// split is most of what makes the app read like a magazine instead of a dashboard.
extension Font {

    /// The day's calorie number. Only ever used once per screen.
    static var plateDisplay: Font { .system(size: 44, weight: .regular, design: .serif) }

    /// Food names, catalog section headers.
    static var plateTitle: Font { .system(size: 24, weight: .regular, design: .serif) }

    /// Smaller serif — card titles in the catalog grid.
    static var plateTitleSmall: Font { .system(size: 17, weight: .regular, design: .serif) }

    /// Chat body.
    static var plateBody: Font { .system(size: 16, weight: .regular) }

    /// Buttons, inline controls.
    static var plateLabel: Font { .system(size: 13, weight: .medium) }

    /// All-caps micro labels: macro names, dates, units.
    static var plateCaption: Font { .system(size: 11, weight: .medium) }

    /// Numerals inside dense contexts (macro values). Monospaced digits so numbers
    /// don't jitter while they animate.
    static var plateNumeric: Font { .system(size: 15, weight: .medium).monospacedDigit() }
}

extension Text {
    /// Uppercase micro-label with the tracking the caption size needs to breathe.
    func plateCaptionStyle(_ color: Color = Palette.inkFaint) -> some View {
        self
            .font(.plateCaption)
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    /// Body copy with Plate's line spacing. Chat bubbles use this.
    func plateBodyStyle() -> some View {
        font(.plateBody).lineSpacing(5)
    }
}
