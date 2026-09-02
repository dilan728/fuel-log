import SwiftUI

/// A logged food, inline in the conversation.
///
/// The image is square and generous relative to the text because it is the thing the
/// eye should land on — this card is the same object that will appear in the Catalog,
/// and it is supposed to feel like a clipping rather than a table row.
struct FoodCard: View {
    let entry: FoodEntry
    var namespace: Namespace.ID?
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                image
                    .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.plateTitleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)

                    Text(entry.subtitle)
                        .font(.plateCaption)
                        .tracking(0.4)
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)

                    // Below a few calories the macro split is rounding noise, and a
                    // solid bar for a black coffee reads as a bug.
                    if entry.facts.calories >= 15 {
                        MacroBar(facts: entry.facts)
                            .padding(.top, 3)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(entry.facts.calories.rounded()))")
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                    Text("cal")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.paperRaised)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.name), \(entry.quantity.display), "
            + "\(Int(entry.facts.calories.rounded())) calories"
        )
    }

    @ViewBuilder
    private var image: some View {
        if let namespace {
            FoodImageView(entry: entry, cornerRadius: 14)
                .matchedGeometryEffect(id: entry.id, in: namespace)
        } else {
            FoodImageView(entry: entry, cornerRadius: 14)
        }
    }
}

/// The three macro densities as a single 3pt bar. Same vocabulary as the ring, at a
/// size where a ring would be illegible.
struct MacroBar: View {
    let facts: NutritionFacts
    var height: CGFloat = 3

    var body: some View {
        let split = facts.energySplit
        let total = split.protein + split.carbs + split.fat

        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                if total > 0.001 {
                    segment(Palette.protein, split.protein / total, proxy.size.width)
                    segment(Palette.carbs, split.carbs / total, proxy.size.width)
                    segment(Palette.fat, split.fat / total, proxy.size.width)
                } else {
                    Capsule().fill(Palette.ringTrack)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: 92)
        .accessibilityHidden(true)
    }

    private func segment(_ color: Color, _ fraction: Double, _ width: CGFloat) -> some View {
        Capsule()
            .fill(color)
            // Subtract the inter-segment spacing so three segments still total the
            // full width rather than overflowing by 3pt.
            .frame(width: max((width - 3) * fraction, 0))
    }
}

/// Cards depress slightly and lose a little shadow when touched. The scale is small
/// enough that it registers as tactile rather than as an animation.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.012 : 0)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}
