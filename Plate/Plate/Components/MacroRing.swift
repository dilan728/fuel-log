import SwiftUI

/// The day at a glance.
///
/// The ring does two jobs with one shape: how far through the day's energy you are
/// (arc length) and what that energy was made of (the three macro densities within
/// the arc). With no target set the ring simply draws full and reads as composition
/// only — the app never invents a goal in order to have something to be behind on.
struct MacroRing: View {
    var facts: NutritionFacts
    var target: Double?
    var lineWidth: CGFloat = 7
    /// Animated fill, so the ring draws itself on appearance.
    var isAnimated: Bool = true

    @State private var appeared = false

    /// How much of the circle is used. Overshooting a target keeps filling past 1 and
    /// the ring laps — a hard stop at full would hide the overage.
    private var fillFraction: Double {
        guard let target, target > 0 else { return facts.calories > 0 ? 1 : 0 }
        return min(facts.calories / target, 1)
    }

    private var lapFraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(max(facts.calories / target - 1, 0), 1)
    }

    private var segments: [(color: Color, start: Double, end: Double)] {
        let split = facts.energySplit
        let total = split.protein + split.carbs + split.fat
        guard total > 0.001 else { return [] }

        let scale = fillFraction * (appeared || !isAnimated ? 1 : 0)
        var cursor = 0.0
        var result: [(Color, Double, Double)] = []
        for (color, share) in [
            (Palette.protein, split.protein),
            (Palette.carbs, split.carbs),
            (Palette.fat, split.fat)
        ] {
            let length = share / total * scale
            guard length > 0.0005 else { continue }
            result.append((color, cursor, cursor + length))
            cursor += length
        }
        return result
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(
                        segment.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
            }
            // The flow is applied to the segments as a group so the animated gradient
            // is continuous across macro boundaries rather than restarting at each one.
            .modifier(EmberFlowModifier())

            // A second, thinner ring for calories past the target.
            if lapFraction > 0 {
                Circle()
                    .trim(from: 0, to: lapFraction * (appeared || !isAnimated ? 1 : 0))
                    .stroke(
                        Palette.ember.opacity(0.9),
                        style: StrokeStyle(lineWidth: lineWidth * 0.42, lineCap: .round)
                    )
                    .padding(lineWidth * 0.75)
            }
        }
        .rotationEffect(.degrees(-90))
        .plateAnimation(Motion.bounce, value: fillFraction)
        .plateAnimation(Motion.bounce, value: appeared)
        .onAppear {
            guard isAnimated else { return }
            // A beat before filling, so the ring is visibly drawn rather than just
            // being there when the screen arrives.
            withAnimation(Motion.bounce.delay(0.12)) { appeared = true }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = ["\(Int(facts.calories.rounded())) calories"]
        if let target { parts.append("of a \(Int(target)) calorie target") }
        parts.append("\(Int(facts.protein.rounded())) grams protein")
        parts.append("\(Int(facts.carbs.rounded())) grams carbohydrate")
        parts.append("\(Int(facts.fat.rounded())) grams fat")
        return parts.joined(separator: ", ")
    }
}

/// Applies the animated ember gradient across whatever it wraps.
private struct EmberFlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        ShaderClock(frozenAt: 1.4) { time in
            content.visualEffect { view, proxy in
                view.colorEffect(
                    PlateShaders.emberFlow(
                        size: proxy.size,
                        time: time,
                        warm: Palette.ember,
                        cool: Palette.ember.opacity(0.55)
                    )
                )
            }
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        MacroRing(
            facts: NutritionFacts(calories: 1840, protein: 96, carbs: 210, fat: 61),
            target: 2200
        )
        .frame(width: 120, height: 120)

        MacroRing(
            facts: NutritionFacts(calories: 2600, protein: 120, carbs: 280, fat: 90),
            target: 2200
        )
        .frame(width: 120, height: 120)
    }
    .padding(40)
    .background(Palette.paper)
}
