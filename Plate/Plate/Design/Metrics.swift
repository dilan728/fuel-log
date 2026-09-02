import SwiftUI

/// The measuring system.
///
/// Named `Metrics` rather than `Layout` because SwiftUI already has a `Layout`
/// protocol, and shadowing it silently breaks any custom layout in the module.
///
/// Every gap in the app comes from here. The first version used whatever number looked
/// right at the time — 10, 13, 14, 16, 18, 20 — and the result reads as approximately
/// aligned, which is worse than obviously misaligned because the eye keeps trying to
/// resolve it.
enum Metrics {
    /// Everything sits on a 4pt rhythm.
    static let hair: CGFloat = 2
    static let tight: CGFloat = 4
    static let snug: CGFloat = 8
    static let step: CGFloat = 12
    static let wide: CGFloat = 16
    static let roomy: CGFloat = 24
    static let generous: CGFloat = 32
    static let vast: CGFloat = 48

    /// The single horizontal margin. One value, used everywhere, so every left edge in
    /// the app agrees.
    static let margin: CGFloat = 24

    /// Space between columns in the catalog grid.
    static let gutter: CGFloat = 12

    /// Photographs are barely rounded. A 20pt radius reads as a UI card; print does not
    /// round its images at all, and 3pt is enough to avoid a hard corner on glass.
    static let imageRadius: CGFloat = 3

    /// Interactive surfaces that genuinely are objects — the composer, the send button.
    static let controlRadius: CGFloat = 22
}

/// A rule exactly one device pixel thick.
///
/// `Divider`, and any `frame(height: 0.5)`, lands on a half-pixel at 3x and antialiases
/// into a soft grey smear. Reading `displayScale` and dividing gives a genuinely crisp
/// line, which is most of what separates a typeset page from a web page.
struct Hairline: View {
    var color: Color = Palette.hairline
    var inset: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1 / displayScale)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Content inset to the page margin.
    func plateMargins() -> some View {
        padding(.horizontal, Metrics.margin)
    }
}
