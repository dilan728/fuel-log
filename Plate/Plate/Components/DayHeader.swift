import SwiftUI

/// The day's masthead: date, energy, ring.
///
/// Collapses as the thread scrolls — not by fading, which would leave a ghost over the
/// content, but by shrinking the number and pulling the ring in until only a compact
/// bar remains. `collapse` is 0…1 and is driven by scroll offset.
struct DayHeader: View {
    let day: DayID
    let facts: NutritionFacts
    let target: Double?
    var collapse: Double = 0
    var onTapRing: () -> Void = {}

    private var eased: Double { Curve.easeInOut(collapse) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title)
                    .plateCaptionStyle(Palette.inkFaint)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(calorieText)
                        .font(.system(
                            size: 44 - 20 * eased,
                            weight: .regular,
                            design: .serif
                        ))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(target == nil ? "cal" : "of \(Int(target ?? 0))")
                        .font(.plateCaption)
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                        .opacity(1 - eased * 0.5)
                }
            }

            Spacer(minLength: 8)

            Button(action: onTapRing) {
                MacroRing(facts: facts, target: target, lineWidth: 7 - 1.5 * eased)
                    .frame(width: 58 - 16 * eased, height: 58 - 16 * eased)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 44)
        .padding(.bottom, 10 - 4 * eased)
    }

    private var calorieText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: facts.calories.rounded())) ?? "0"
    }
}

/// The three macros spelled out. Shown under the header when there is room, and in the
/// entry detail sheet.
struct MacroLegend: View {
    let facts: NutritionFacts
    var proteinTarget: Double?

    var body: some View {
        HStack(spacing: 18) {
            item("Protein", facts.protein, Palette.protein, target: proteinTarget)
            item("Carbs", facts.carbs, Palette.carbs, target: nil)
            item("Fat", facts.fat, Palette.fat, target: nil)
            if let fiber = facts.fiber, fiber > 0.5 {
                item("Fibre", fiber, Palette.inkFaint, target: nil)
            }
        }
    }

    private func item(_ name: String, _ grams: Double, _ color: Color, target: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(name).plateCaptionStyle(Palette.inkFaint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(grams.rounded()))")
                    .font(.plateNumeric)
                    .foregroundStyle(Palette.ink)
                Text("g")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.inkFaint)
                if let target, target > 0 {
                    Text("/ \(Int(target))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(Int(grams.rounded())) grams")
    }
}
