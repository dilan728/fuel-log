import SwiftUI

/// The day's energy, as a measure rather than a ring.
///
/// A ring is a fitness-tracker idiom and it fights the page: it is a circle in a layout
/// made of columns and rules, it cannot align to anything, and at the small sizes a
/// header allows it degrades into three unreadable ticks. A horizontal measure spans the
/// text column exactly, doubles as the header's dividing rule, and reads like an
/// instrument — which is the register this app wants.
///
/// The rule's full length *is* the target, so the fill needs no separate scale.
struct EnergyRule: View {
    var facts: NutritionFacts
    var target: Double?
    var thickness: CGFloat = 2.5
    var isAnimated: Bool = true

    @State private var hasAppeared = false

    /// Fraction of the target consumed, capped at the rule's length.
    private var fill: Double {
        guard let target, target > 0 else { return facts.calories > 0 ? 1 : 0 }
        return min(facts.calories / target, 1)
    }

    /// Anything past the target, shown as a second pass over the same rule.
    private var overflow: Double {
        guard let target, target > 0 else { return 0 }
        return min(max(facts.calories / target - 1, 0), 1)
    }

    private var segments: [(color: Color, share: Double)] {
        let split = facts.energySplit
        let total = split.protein + split.carbs + split.fat
        guard total > 0.001 else { return [] }
        return [
            (Palette.protein, split.protein / total),
            (Palette.carbs, split.carbs / total),
            (Palette.fat, split.fat / total)
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = (hasAppeared || !isAnimated) ? 1.0 : 0.0

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Palette.track)
                    .frame(height: thickness)

                // Butted, not spaced. Adjacent segments of the same hue family read as
                // one measure; a gap between them reads as three separate things.
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: width * fill * segment.share * scale)
                    }
                }
                .frame(height: thickness)

                if overflow > 0 {
                    Rectangle()
                        .fill(Palette.ember)
                        .frame(width: width * overflow * scale, height: thickness)
                        .offset(y: thickness + 1.5)
                }
            }
            .frame(height: thickness, alignment: .leading)
        }
        .frame(height: thickness)
        .clipShape(Rectangle())
        .plateAnimation(Motion.bounce, value: fill)
        .plateAnimation(Motion.bounce, value: hasAppeared)
        .onAppear {
            guard isAnimated else { return }
            withAnimation(Motion.bounce.delay(0.08)) { hasAppeared = true }
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

/// The same measure at row scale, for a single food.
struct MacroBar: View {
    let facts: NutritionFacts
    /// `.infinity` fills the available width.
    var width: CGFloat = 54
    var thickness: CGFloat = 2

    var body: some View {
        let split = facts.energySplit
        let total = split.protein + split.carbs + split.fat

        GeometryReader { proxy in
            let available = width.isFinite ? width : proxy.size.width
            HStack(spacing: 0) {
                if total > 0.001 {
                    Rectangle().fill(Palette.protein).frame(width: available * split.protein / total)
                    Rectangle().fill(Palette.carbs).frame(width: available * split.carbs / total)
                    Rectangle().fill(Palette.fat).frame(width: available * split.fat / total)
                } else {
                    Rectangle().fill(Palette.track).frame(width: available)
                }
            }
            .frame(height: thickness)
        }
        .frame(width: width.isFinite ? width : nil, height: thickness)
        .frame(maxWidth: width.isFinite ? nil : .infinity)
        .accessibilityHidden(true)
    }
}

/// Protein / carbohydrate / fat as figures. Uppercase micro labels, tabular values.
struct MacroFigures: View {
    let facts: NutritionFacts
    var spacing: CGFloat = Metrics.step

    var body: some View {
        HStack(spacing: spacing) {
            figure("P", facts.protein)
            figure("C", facts.carbs)
            figure("F", facts.fat)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Int(facts.protein.rounded())) grams protein, "
            + "\(Int(facts.carbs.rounded())) grams carbohydrate, "
            + "\(Int(facts.fat.rounded())) grams fat"
        )
    }

    private func figure(_ symbol: String, _ grams: Double) -> some View {
        HStack(spacing: 3) {
            Text(symbol).typeStyle(.micro, Palette.inkFaint)
            Text("\(Int(grams.rounded()))").typeStyle(.numeric, Palette.inkSoft)
        }
    }
}
