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
