import SwiftUI

/// Film grain, as a transparent layer.
///
/// Must be an overlay rather than a `colorEffect` on the content: a shader applied to
/// an ancestor of a `ScrollView` stops the scroll view's content from rendering at all.
/// Drawing the grain onto its own rectangle and compositing it over the top sidesteps
/// that entirely, and costs one full-screen quad.
struct GrainOverlay: View {
    var intensity: Double = 0.055
    var isActive: Bool = true

    var body: some View {
        ShaderClock(isActive: isActive, frozenAt: 2.1) { time in
            Rectangle()
                .fill(.white)
                .visualEffect { content, proxy in
                    content.colorEffect(
                        ShaderLibrary.grainOverlay(
                            .float2(proxy.size),
                            .float(Float(time)),
                            .float(Float(intensity))
                        )
                    )
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Elliptical vignette, as a transparent layer. Same constraint as `GrainOverlay`.
struct VignetteOverlay: View {
    var strength: Double = 0.42
    var radius: Double = 0.85

    var body: some View {
        Rectangle()
            .fill(.white)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.vignetteOverlay(
                        .float2(proxy.size),
                        .float(Float(strength)),
                        .float(Float(radius))
                    )
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Grain and vignette over a scrolling surface, in the right order.
    func plateFilmTreatment(grain: Double = 0.05, vignette: Double = 0.4) -> some View {
        overlay {
            VignetteOverlay(strength: vignette)
        }
        .overlay {
            GrainOverlay(intensity: grain)
        }
    }
}
