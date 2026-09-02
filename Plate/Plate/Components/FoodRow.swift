import SwiftUI

/// A logged food, as a line in a ledger.
///
/// Not a card. A white rounded rectangle with a drop shadow is the single most generic
/// object in mobile design, and a column of them turns a page into a feed. Rules and
/// alignment do the same structural job without the visual noise, and they let the
/// photographs be the only things on the page with weight.
struct FoodRow: View {
    let entry: FoodEntry
    var namespace: Namespace.ID?
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Metrics.step) {
                image
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .typeStyle(.subtitle)
                        .lineLimit(1)

                    // No macro bar here. It competed with the meta line for width and
                    // truncated it ("1 HANDFUL · BREAKF…"), to convey something the
                    // header measure already says and the detail sheet says properly.
                    Text(entry.subtitle)
                        .typeStyle(.micro, Palette.inkFaint)
                        .lineLimit(1)
                }

                Spacer(minLength: Metrics.snug)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(entry.facts.calories.rounded()))")
                        .typeStyle(.numericLarge)
                    Text("cal")
                        .typeStyle(.unit, Palette.inkFaint)
                }
            }
            .padding(.vertical, Metrics.step)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.name), \(entry.quantity.display), "
            + "\(Int(entry.facts.calories.rounded())) calories"
        )
    }

    @ViewBuilder
    private var image: some View {
        if let namespace {
            FoodImageView(entry: entry, cornerRadius: Metrics.imageRadius, zoom: 1.55)
                .matchedGeometryEffect(id: entry.id, in: namespace)
        } else {
            FoodImageView(entry: entry, cornerRadius: Metrics.imageRadius, zoom: 1.55)
        }
    }
}

/// A run of food rows, ruled.
struct FoodLedger: View {
    let entries: [FoodEntry]
    var namespace: Namespace.ID?
    var onTap: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Hairline(inset: 52 + Metrics.step) }
                FoodRow(entry: entry, namespace: namespace) { onTap(entry.id) }
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .plateAnimation(Motion.bounce, value: entries.count)
    }
}

/// Rows depress by tinting, not by scaling. A row is part of a page; scaling it lifts it
/// off the page and undoes the point of not making it a card.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.inkGhost.opacity(0.5) : .clear)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

/// For things that genuinely are objects — buttons, chips, tiles.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}
