import SwiftUI

/// Typed access to `Plate.metal`.
///
/// Shader arguments are positional and untyped at the call site, which makes them a
/// classic source of silent visual bugs — swap two floats and you get a plausible but
/// wrong image with no error. Everything funnels through this file so each shader's
/// signature is written down exactly once.
enum PlateShaders {

    /// Session-relative clock. Metal floats are 32-bit; feeding them
    /// `timeIntervalSinceReferenceDate` (~8.2e8) leaves about 1/16 s of precision and
    /// makes every time-based effect visibly quantise. Relative-to-launch keeps us
    /// near zero where float32 has plenty of resolution.
    static let epoch = Date()

    static func now() -> Double { Date().timeIntervalSince(epoch) }

    // MARK: Signatures

    static func grain(size: CGSize, time: Double, intensity: Double) -> Shader {
        ShaderLibrary.plateGrain(
            .float2(size),
            .float(Float(time)),
            .float(Float(intensity))
        )
    }

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

    static func tokenBloom(head: CGPoint, radius: CGFloat, strength: Double, tint: Color) -> Shader {
        ShaderLibrary.tokenBloom(
            .float2(head),
            .float(Float(radius)),
            .float(Float(strength)),
            .color(tint)
        )
    }

    static func liquidGlass(
        size: CGSize,
        cornerRadius: CGFloat,
        thickness: CGFloat,
        lightAngle: Double,
        specular: Color
    ) -> Shader {
        ShaderLibrary.liquidGlass(
            .float2(size),
            .float(Float(cornerRadius)),
            .float(Float(thickness)),
            .float(Float(lightAngle)),
            .color(specular)
        )
    }

    static func glassRim(
        size: CGSize,
        cornerRadius: CGFloat,
        thickness: CGFloat,
        lightAngle: Double,
        specular: Color
    ) -> Shader {
        ShaderLibrary.glassRim(
            .float2(size),
            .float(Float(cornerRadius)),
            .float(Float(thickness)),
            .float(Float(lightAngle)),
            .color(specular)
        )
    }

    static func emberFlow(size: CGSize, time: Double, warm: Color, cool: Color) -> Shader {
        ShaderLibrary.emberFlow(
            .float2(size),
            .float(Float(time)),
            .color(warm),
            .color(cool)
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

    static func softVignette(size: CGSize, strength: Double, radius: Double) -> Shader {
        ShaderLibrary.softVignette(
            .float2(size),
            .float(Float(strength)),
            .float(Float(radius))
        )
    }

}

// MARK: - Time source

/// Drives time-varying shaders.
///
/// Two behaviours worth knowing about: it hands out a *session-relative* clock (see
/// `PlateShaders.epoch`), and when `isActive` is false it collapses to a single static
/// evaluation. Every animated shader in the app is wrapped in one of these and told
/// whether it is on screen, so off-screen cards cost nothing.
struct ShaderClock<Content: View>: View {
    var isActive: Bool = true
    /// A fixed time used when the clock is stopped. Chosen per-effect so the frozen
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

    /// Film grain. Applied once, high in the Catalog hierarchy — not per card.
    func plateGrain(intensity: Double = 0.055, isActive: Bool = true) -> some View {
        ShaderClock(isActive: isActive) { time in
            self.visualEffect { content, proxy in
                content.colorEffect(
                    PlateShaders.grain(size: proxy.size, time: time, intensity: intensity)
                )
            }
        }
    }

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

    /// Warm bloom trailing a streaming write head.
    func plateTokenBloom(head: CGPoint, radius: CGFloat = 46, strength: Double = 1, tint: Color) -> some View {
        visualEffect { content, _ in
            content.layerEffect(
                PlateShaders.tokenBloom(head: head, radius: radius, strength: strength, tint: tint),
                maxSampleOffset: CGSize(width: 4, height: 4)
            )
        }
    }

    /// Refracts whatever this view has already rasterized. Works on ordinary content —
    /// images, cards, view hierarchies. It does *not* work over a system material,
    /// which never rasterizes into the shader's layer; use `plateGlassRim` there.
    func plateLiquidGlass(
        cornerRadius: CGFloat,
        thickness: CGFloat = 14,
        lightAngle: Double = -.pi / 2.6,
        specular: Color
    ) -> some View {
        visualEffect { content, proxy in
            content.layerEffect(
                PlateShaders.liquidGlass(
                    size: proxy.size,
                    cornerRadius: cornerRadius,
                    thickness: thickness,
                    lightAngle: lightAngle,
                    specular: specular
                ),
                maxSampleOffset: CGSize(width: thickness + 4, height: thickness + 4)
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

    /// Analytic rim lighting for a pane of glass. Draw this over a real material.
    func plateGlassRim(
        cornerRadius: CGFloat,
        thickness: CGFloat = 14,
        lightAngle: Double = -.pi * 0.62,
        specular: Color
    ) -> some View {
        visualEffect { content, proxy in
            content.colorEffect(
                PlateShaders.glassRim(
                    size: proxy.size,
                    cornerRadius: cornerRadius,
                    thickness: thickness,
                    lightAngle: lightAngle,
                    specular: specular
                )
            )
        }
    }

    func plateVignette(strength: Double = 0.45, radius: Double = 0.78) -> some View {
        visualEffect { content, proxy in
            content.colorEffect(
                PlateShaders.softVignette(size: proxy.size, strength: strength, radius: radius)
            )
        }
    }

    /// Sheen for a card whose image is being generated.
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
