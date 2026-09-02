import SwiftUI

/// A pane of glass.
///
/// A real `.ultraThinMaterial` provides the blur — the system is the only thing that
/// can sample the backdrop — and `glassRim` is drawn over it to add the rim lighting,
/// counter-highlight and face sheen that make it read as a solid object with an edge
/// rather than as a blurred rectangle.
///
/// The refraction shader is deliberately *not* used here: a `layerEffect` over a
/// material samples an empty layer, which renders the pane black.
struct GlassSurface: View {
    var cornerRadius: CGFloat = 24
    /// How far in from the rim the lighting reaches, in points.
    var thickness: CGFloat = 14
    /// Direction of the key light, in radians. Upper-left, matching the procedural
    /// plate renderer, so the whole app agrees where the light is coming from.
    var lightAngle: Double = -.pi * 0.62
    var material: Material = .ultraThinMaterial

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var specular: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.white
    }

    var body: some View {
        if reduceTransparency {
            shape
                .fill(Palette.paperFloating)
                .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 0.5))
        } else {
            shape
                .fill(material)
                .overlay {
                    shape
                        .fill(.white)
                        .plateGlassRim(
                            cornerRadius: cornerRadius,
                            thickness: thickness,
                            lightAngle: lightAngle,
                            specular: specular
                        )
                        .allowsHitTesting(false)
                }
                .overlay {
                    // A hairline so the pane keeps a crisp boundary on the unlit side,
                    // where the specular falls to nothing.
                    shape.strokeBorder(
                        Palette.ink.opacity(colorScheme == .dark ? 0.16 : 0.07),
                        lineWidth: 0.5
                    )
                }
                .compositingGroup()
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.09), radius: 12, y: 4)
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
