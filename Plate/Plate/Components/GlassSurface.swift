import SwiftUI

/// A pane of glass.
///
/// The refraction is real: the shape is filled with a system material, which has
/// already rasterized a blurred copy of whatever is behind it, and `liquidGlass` then
/// bends the sample position along the shape's own surface normal near the rim. The
/// middle of the pane is left undistorted so text laid over it stays crisp.
struct GlassSurface: View {
    var cornerRadius: CGFloat = 24
    /// How far in from the rim the refraction reaches, in points.
    var thickness: CGFloat = 14
    /// Direction of the key light, in radians. Default is upper-left, matching the
    /// procedural plate renderer so the whole app agrees where the light is.
    var lightAngle: Double = -.pi * 0.62
    var material: Material = .ultraThinMaterial

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var specular: Color {
        colorScheme == .dark ? Color.white.opacity(0.34) : Color.white.opacity(0.55)
    }

    var body: some View {
        if reduceTransparency {
            shape
                .fill(Palette.paperFloating)
                .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 0.5))
        } else {
            shape
                .fill(material)
                .plateLiquidGlass(
                    cornerRadius: cornerRadius,
                    thickness: thickness,
                    lightAngle: lightAngle,
                    specular: specular
                )
                .overlay(
                    // A hairline that survives the refraction, so the pane always has
                    // a crisp boundary even where the specular falls off.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.20 : 0.60),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
                )
        }
    }
}

extension View {
    /// Places a `GlassSurface` behind this view with consistent padding.
    func glassBackground(
        cornerRadius: CGFloat = 24,
        thickness: CGFloat = 14,
        padding: EdgeInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    ) -> some View {
        self
            .padding(padding)
            .background(GlassSurface(cornerRadius: cornerRadius, thickness: thickness))
    }
}
