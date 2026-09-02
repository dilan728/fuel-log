import SwiftUI

/// The day's masthead.
///
/// Three lines and a rule: what day it is and what it was made of, the figure, and the
/// measure. The measure is full-column width, so it doubles as the header's dividing
/// rule — one element doing two jobs, which is why the header needs no separate border.
///
/// `collapse` runs 0…1 from scroll offset. The figure interpolates rather than switching
/// between two sizes, because a font that jumps a step mid-scroll is more distracting
/// than one that never moved.
struct DayHeader: View {
    let day: DayID
    let facts: NutritionFacts
    let target: Double?
    var collapse: Double = 0

    private var eased: Double { Curve.easeInOut(collapse) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateLine)
                    .typeStyle(.micro, Palette.inkFaint)
                Spacer(minLength: Metrics.step)
                MacroFigures(facts: facts)
                    .opacity(1 - eased * 0.55)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(energyText)
                    .font(.system(size: 44 - 18 * eased, weight: .regular, design: .serif))
                    .tracking(-1.4 + 0.7 * eased)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                    .opticalLeading(forSize: 44 - 18 * eased)

                if let target {
                    Text("of \(Self.figure(target))")
                        .typeStyle(.micro, Palette.inkFaint)
                } else {
                    Text("cal")
                        .typeStyle(.micro, Palette.inkFaint)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, Metrics.snug - 4 * eased)
            .padding(.bottom, Metrics.step - 4 * eased)

            EnergyRule(facts: facts, target: target)
        }
        .plateMargins()
        .padding(.top, Metrics.vast - 6 * eased)
        .padding(.bottom, Metrics.step)
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let stamp = formatter.string(from: day.date())
        return day.isToday || day.isYesterday ? "\(day.title) · \(stamp)" : stamp
    }

    private var energyText: String { Self.figure(facts.calories) }

    static func figure(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }
}
