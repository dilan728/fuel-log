import SwiftUI

/// Typed access to `Plate.metal`.
///
/// Shader arguments are positional and untyped at the call site, which makes them a
/// classic source of silent visual bugs — swap two floats and you get a plausible but
/// wrong image with no error. Worse, `ShaderLibrary` resolves by name at *runtime*, so
/// a wrapper left behind after its shader is deleted still compiles. Everything funnels
/// through this file so each shader's signature is written down exactly once and the
/// set of wrappers matches the set of entry points.
enum PlateShaders {

    /// Session-relative clock. Metal floats are 32-bit; feeding them
    /// `timeIntervalSinceReferenceDate` (~8.2e8) leaves about 1/16 s of precision and
    /// makes every time-based effect visibly quantise. Relative-to-launch keeps us near
    /// zero, where float32 has plenty of resolution.
    static let epoch = Date()

    static func now() -> Double { Date().timeIntervalSince(epoch) }

    // MARK: Signatures

    static func materialize(size: CGSize, progress: Double, seed: UInt32, tint: Color) -> Shader {
        ShaderLibrary.materialize(
            .float2(size),
            .float(Float(progress)),
            // Map the 32-bit seed into a small float range; the shader only needs
            // decorrelation, not the full entropy, and large floats lose precision.
            .float(Float(seed % 9973) / 97.0),
            .color(tint)
        )
    }

    static func shimmerSweep(size: CGSize, time: Double, sheen: Color) -> Shader {
        ShaderLibrary.shimmerSweep(
            .float2(size),
            .float(Float(time)),
            .color(sheen)
        )
    }

    static func pinchWarp(size: CGSize, amount: Double, chroma: Double) -> Shader {
        ShaderLibrary.pinchWarp(
            .float2(size),
            .float(Float(amount)),
            .float(Float(chroma))
        )
    }
}

// MARK: - Time source

/// Drives time-varying shaders.
///
/// Two behaviours worth knowing about: it hands out a *session-relative* clock (see
/// `PlateShaders.epoch`), and when `isActive` is false it collapses to a single static
/// evaluation, so off-screen work costs nothing.
///
/// Note what it must never contain: animating content. Putting a view whose own
/// animation is in flight inside the timeline closure re-evaluates it every frame and
/// the animation restarts continuously — which is how the macro ring once rendered as
/// three stranded ticks instead of an arc.
struct ShaderClock<Content: View>: View {
    var isActive: Bool = true
    /// A fixed time used when the clock is stopped. Chosen per effect so the frozen
    /// frame is a flattering one rather than whatever t=0 happens to look like.
    var frozenAt: Double = 3.7
    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.plateReduceMotion) private var forcedReduceMotion

    var body: some View {
        let shouldRun = isActive && !reduceMotion && !forcedReduceMotion
        if shouldRun {
            TimelineView(.animation) { context in
                content(context.date.timeIntervalSince(PlateShaders.epoch))
            }
        } else {
            content(frozenAt)
        }
    }
}

// MARK: - View modifiers
//
// `visualEffect` is used throughout rather than `GeometryReader`, because it gives the
// shader the resolved size without changing layout.

extension View {

    /// Reveals content out of noise. `progress` 0…1.
    func plateMaterialize(progress: Double, seed: UInt32, tint: Color) -> some View {
        visualEffect { content, proxy in
            content.layerEffect(
                PlateShaders.materialize(
                    size: proxy.size,
                    progress: progress,
                    seed: seed,
                    tint: tint
                ),
                // The shader scatters by up to 46pt; anything less clips the grains.
                maxSampleOffset: CGSize(width: 48, height: 48)
            )
        }
    }

    /// Lens warp with chromatic divergence. `amount` is signed; 0 is a no-op and the
    /// effect is skipped entirely, so this is cheap to leave attached.
    func platePinchWarp(amount: Double, chroma: Double = 1) -> some View {
        visualEffect { content, proxy in
            content.layerEffect(
                PlateShaders.pinchWarp(size: proxy.size, amount: amount, chroma: chroma),
                maxSampleOffset: CGSize(width: 64, height: 64),
                isEnabled: abs(amount) > 0.001
            )
        }
    }

    /// Sheen for an image that is still being made.
    func plateShimmer(sheen: Color, isActive: Bool = true) -> some View {
        ShaderClock(isActive: isActive) { time in
            self.visualEffect { content, proxy in
                content.colorEffect(
                    PlateShaders.shimmerSweep(size: proxy.size, time: time, sheen: sheen)
                )
            }
        }
    }
}
