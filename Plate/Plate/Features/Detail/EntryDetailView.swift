import SwiftUI

/// One meal, up close.
///
/// Direct manipulation on purpose: adjusting a portion should not require a sentence.
/// Dragging the measure rescales the figures live, which is the fastest way to
/// understand what a portion is actually worth.
struct EntryDetailView: View {
    let reference: AppModel.EntryReference

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var entry: FoodEntry?
    /// Multiplier applied live while dragging; committed on release.
    @State private var scale: Double = 1
    @State private var isConfirmingRemoval = false

    private var session: ThreadSession { app.session(for: reference.day) }
    private var scaledFacts: NutritionFacts { (entry?.facts ?? .zero).scaled(by: scale) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let entry {
                    // Capped and centred rather than full width. At the medium detent a
                    // full-width square is 354pt tall and pushes the figures and the
                    // portion control — the two things this sheet exists for — off the
                    // bottom of the sheet entirely.
                    FoodImageView(entry: entry, cornerRadius: Metrics.imageRadius)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 190)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Metrics.step)

                    heading(entry)
                    figures
                    portion(entry)
                    provenance(entry)
                    actions(entry)
                }
            }
            .padding(.bottom, Metrics.vast)
        }
        .background(Palette.paper)
        .task { await load() }
    }

    // MARK: Sections

    private func heading(_ entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            Text(entry.name)
                .typeStyle(.title)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = entry.detail, !detail.isEmpty {
                Text(detail).typeStyle(.body, Palette.inkSoft)
            }

            Text("\(entry.meal.title) · \(Self.time(entry.loggedAt))")
                .typeStyle(.micro, Palette.inkFaint)
        }
        .plateMargins()
        .padding(.top, Metrics.roomy)
        .padding(.bottom, Metrics.wide)
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: Metrics.step) {
            Hairline()

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(DayHeader.figure(scaledFacts.calories))
                    .typeStyle(.masthead)
                    .contentTransition(.numericText())
                    .opticalLeading(forSize: 44)
                Text("cal").typeStyle(.unit, Palette.inkFaint)
                Spacer(minLength: Metrics.step)
                MacroFigures(facts: scaledFacts, spacing: Metrics.wide)
            }
            .plateMargins()

            MacroBar(facts: scaledFacts, width: .infinity, thickness: 2.5)
                .plateMargins()

            Hairline()
        }
        .padding(.bottom, Metrics.roomy)
        .plateAnimation(Motion.snap, value: scale)
    }

    private func portion(_ entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: Metrics.step) {
            HStack(alignment: .firstTextBaseline) {
                Text("Portion").typeStyle(.micro, Palette.inkFaint)
                Spacer()
                Text(Quantity(amount: entry.quantity.amount * scale, unit: entry.quantity.unit).display)
                    .typeStyle(.numeric, Palette.ink)
            }

            PortionSlider(scale: $scale) { commit(entry) }
        }
        .plateMargins()
        .padding(.bottom, Metrics.roomy)
    }

    private func provenance(_ entry: FoodEntry) -> some View {
        HStack(spacing: Metrics.snug) {
            Rectangle()
                .fill(Self.confidenceColor(entry.confidence))
                .frame(width: 12, height: 2)
            Text(entry.confidence.label).typeStyle(.micro, Palette.inkFaint)
            if case .failed = entry.image {
                Text("· no photo").typeStyle(.micro, Palette.inkFaint)
            }
            Spacer()
        }
        .plateMargins()
        .padding(.bottom, Metrics.roomy)
    }

    private func actions(_ entry: FoodEntry) -> some View {
        VStack(spacing: 0) {
            Hairline()
            Button {
                Task {
                    await session.updateEntry(entry.id) { $0.image = .none }
                    await load()
                    app.ensureImage(for: entry, on: reference.day)
                }
            } label: {
                actionLabel("New picture", symbol: "sparkles", tint: Palette.inkSoft)
            }
            .buttonStyle(RowPressStyle())

            Hairline()
            Button {
                if isConfirmingRemoval {
                    Task {
                        await session.deleteEntry(entry.id)
                        await app.refreshLoggedDays()
                        dismiss()
                    }
                } else {
                    withAnimation(Motion.snap) { isConfirmingRemoval = true }
                    Haptics.shared.select()
                }
            } label: {
                actionLabel(
                    isConfirmingRemoval ? "Tap again to remove" : "Remove",
                    symbol: "minus",
                    tint: Palette.alert
                )
            }
            .buttonStyle(RowPressStyle())
            Hairline()
        }
    }

    private func actionLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: Metrics.step) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title).typeStyle(.body)
            Spacer()
        }
        .foregroundStyle(tint)
        .plateMargins()
        .padding(.vertical, Metrics.wide)
        .contentShape(Rectangle())
    }

    // MARK: Data

    private func load() async {
        await session.loadIfNeeded()
        entry = session.entry(reference.id)
        scale = 1
    }

    private func commit(_ entry: FoodEntry) {
        guard abs(scale - 1) > 0.001 else { return }
        let factor = scale
        Task {
            await session.updateEntry(entry.id) { stored in
                stored.quantity.amount *= factor
                stored.facts = stored.facts.scaled(by: factor)
                // A hand-adjusted portion is exactly as good as measured — the user just
                // told us what it was.
                stored.confidence = .measured
            }
            await load()
            await app.refreshLoggedDays()
            Haptics.shared.commit()
        }
    }

    private static func confidenceColor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .measured: return Palette.ember
        case .estimated: return Palette.carbs
        case .guessed: return Palette.inkGhost
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// A portion multiplier you drag. Detents at the halves and whole numbers, so landing on
/// "1½" is easy and landing on "1.47" takes deliberate effort.
private struct PortionSlider: View {
    @Binding var scale: Double
    var onCommit: () -> Void

    private let stops: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let position = normalized(scale) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Palette.track)
                    .frame(height: 2)

                // Detent ticks, so the scale is legible before you touch it.
                ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                    Rectangle()
                        .fill(Palette.track)
                        .frame(width: 1, height: 6)
                        .offset(x: normalized(stop) * width)
                }

                Rectangle()
                    .fill(Palette.ember)
                    .frame(width: max(position, 2), height: 2)

                Capsule()
                    .fill(Palette.ember)
                    .frame(width: 3, height: 18)
                    .offset(x: position - 1.5)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        let next = snap(denormalized(fraction))
                        if next != scale { Haptics.shared.select() }
                        scale = next
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: 22)
        .accessibilityValue("\(String(format: "%.2f", scale)) times the logged portion")
    }

    private func normalized(_ value: Double) -> Double {
        Curve.remap(value, stops.first ?? 0.25, stops.last ?? 3, 0, 1)
    }

    private func denormalized(_ fraction: Double) -> Double {
        (stops.first ?? 0.25) + fraction * ((stops.last ?? 3) - (stops.first ?? 0.25))
    }

    /// Pulls toward a stop when close, without preventing values in between.
    private func snap(_ value: Double) -> Double {
        guard let nearest = stops.min(by: { abs($0 - value) < abs($1 - value) }) else { return value }
        return abs(nearest - value) < 0.08 ? nearest : (value * 100).rounded() / 100
    }
}
