import SwiftUI

/// Three springs, used everywhere. If a new animation needs a fourth curve, that is
/// usually a sign the interaction is wrong, not that the palette of curves is too small.
enum Motion {

    /// Taps, toggles, chips. Fast, barely overshoots.
    static let snap = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Page and sheet transitions. Long enough to read as a movement, not a cut.
    static let glide = Animation.spring(response: 0.55, dampingFraction: 0.88)

    /// Arrivals: a new food card, a ring filling. This is the only curve allowed
    /// to visibly overshoot.
    static let bounce = Animation.spring(response: 0.48, dampingFraction: 0.62)

    /// Ambient, non-interactive motion (background wash, idle shimmer).
    static let drift = Animation.spring(response: 1.1, dampingFraction: 0.96)

    /// The reduced-motion substitute for everything above.
    static let reduced = Animation.easeOut(duration: 0.2)

    /// Duration of the image materialize reveal, in seconds.
    static let materializeDuration: Double = 0.9
}

// MARK: - Reduce Motion

private struct ReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Mirrors `accessibilityReduceMotion` but can also be forced on for previews.
    var plateReduceMotion: Bool {
        get { self[ReducedMotionKey.self] }
        set { self[ReducedMotionKey.self] = newValue }
    }
}

extension View {
    /// Applies `animation` normally, or `Motion.reduced` when Reduce Motion is on.
    /// Use this instead of `.animation(_:value:)` for anything expressive.
    func plateAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(PlateAnimationModifier(animation: animation, value: value))
    }
}

private struct PlateAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.plateReduceMotion) private var forcedReduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        let reduce = systemReduceMotion || forcedReduceMotion
        return content.animation(reduce ? Motion.reduced : animation, value: value)
    }
}

// MARK: - Curves used outside of Animation

enum Curve {
    /// Symmetric ease used by hand-driven interpolation (pinch progress, parallax).
    static func easeInOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    /// Decelerating curve for values that should settle, not accelerate.
    static func easeOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    /// Rubber-band resistance past a boundary, as used by UIScrollView.
    /// `offset` is how far past the edge; `dimension` is the container extent.
    static func rubberBand(offset: Double, dimension: Double, coefficient: Double = 0.55) -> Double {
        guard dimension > 0 else { return 0 }
        let sign: Double = offset < 0 ? -1 : 1
        let x = abs(offset)
        return sign * (1 - (1 / (x * coefficient / dimension + 1))) * dimension
    }

    /// Hermite ramp between two edges. The workhorse for crossfades: a linear fade
    /// leaves both layers at half strength in the middle, which reads as a wash rather
    /// than as one thing replacing another.
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Maps `value` from one range to another, clamped.
    static func remap(_ value: Double, _ inLow: Double, _ inHigh: Double, _ outLow: Double, _ outHigh: Double) -> Double {
        guard inHigh != inLow else { return outLow }
        let t = min(max((value - inLow) / (inHigh - inLow), 0), 1)
        return outLow + (outHigh - outLow) * t
    }
}
