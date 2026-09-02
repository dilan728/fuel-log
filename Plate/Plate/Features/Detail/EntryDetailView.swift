import SwiftUI

/// One meal, up close.
///
/// Direct manipulation on purpose: adjusting a portion should not require a sentence.
/// Changing the amount rescales the macros live — the numbers move under your thumb,
/// which is the fastest way to understand what a portion is worth.
struct EntryDetailView: View {
    let reference: AppModel.EntryReference

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var entry: FoodEntry?
    /// Multiplier applied live while dragging; committed on release.
    @State private var scale: Double = 1
    @State private var isConfirmingDelete = false

    private var session: ThreadSession { app.session(for: reference.day) }

    private var scaledFacts: NutritionFacts {
        (entry?.facts ?? .zero).scaled(by: scale)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let entry {
                    FoodImageView(entry: entry, cornerRadius: 24)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    header(entry)
                    portionControl(entry)
                    macros
                    provenance(entry)
                    actions(entry)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Palette.paper)
        .task { await load() }
    }

    // MARK: Sections

    private func header(_ entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.plateTitle)
                .foregroundStyle(Palette.ink)

            if let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(.plateBody)
                    .foregroundStyle(Palette.inkSoft)
            }

            Text("\(entry.meal.title) · \(timeText(entry.loggedAt))")
                .plateCaptionStyle()
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func portionControl(_ entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Portion").plateCaptionStyle()
                Spacer()
                Text(Quantity(amount: entry.quantity.amount * scale, unit: entry.quantity.unit).display)
                    .font(.plateNumeric)
                    .foregroundStyle(Palette.ink)
            }

            PortionSlider(scale: $scale) { commit(entry) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var macros: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(scaledFacts.calories.rounded()))")
                    .font(.plateDisplay)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("calories").plateCaptionStyle()
            }

            MacroLegend(facts: scaledFacts, proteinTarget: nil)

            MacroBar(facts: scaledFacts, height: 5)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .plateAnimation(Motion.snap, value: scale)
    }

    private func provenance(_ entry: FoodEntry) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(confidenceColor(entry.confidence))
                .frame(width: 5, height: 5)
            Text(entry.confidence.label)
                .font(.plateCaption)
                .tracking(0.5)
                .foregroundStyle(Palette.inkFaint)

            if case .failed = entry.image {
                Text("· no photo")
                    .font(.plateCaption)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func actions(_ entry: FoodEntry) -> some View {
        HStack(spacing: 10) {
            if FoodImageService.shared.isConfigured {
                Button {
                    Task {
                        await session.updateEntry(entry.id) { $0.image = .none }
                        await load()
                        app.ensureImage(for: entry, on: reference.day)
                    }
                } label: {
                    Label("New photo", systemImage: "sparkles")
                        .font(.plateLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Palette.inkGhost.opacity(0.4))
                        }
                }
                .buttonStyle(PressableCardStyle())
                .foregroundStyle(Palette.inkSoft)
            }

            Button {
                if isConfirmingDelete {
                    Task {
                        await session.deleteEntry(entry.id)
                        await app.refreshLoggedDays()
                        dismiss()
                    }
                } else {
                    withAnimation(Motion.snap) { isConfirmingDelete = true }
                    Haptics.shared.select()
                }
            } label: {
                Label(
                    isConfirmingDelete ? "Tap again to remove" : "Remove",
                    systemImage: "trash"
                )
                .font(.plateLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Palette.alert.opacity(isConfirmingDelete ? 0.16 : 0.07))
                }
            }
            .buttonStyle(PressableCardStyle())
            .foregroundStyle(Palette.alert)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
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
                // A hand-adjusted portion is exactly as good as measured — the user
                // just told us what it was.
                stored.confidence = .measured
            }
            await load()
            await app.refreshLoggedDays()
            Haptics.shared.commit()
        }
    }

    private func confidenceColor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .measured: return Palette.ember
        case .estimated: return Palette.carbs
        case .guessed: return Palette.inkFaint
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// A portion multiplier you drag. Detents at the halves and whole numbers, so landing
/// on "1½" is easy and landing on "1.47" takes deliberate effort.
private struct PortionSlider: View {
    @Binding var scale: Double
    var onCommit: () -> Void

    private let stops: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let position = normalized(scale) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.ringTrack)
                    .frame(height: 4)

                Capsule()
                    .fill(Palette.ember)
                    .frame(width: max(position, 4), height: 4)

                Circle()
                    .fill(Palette.paperRaised)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                    .overlay(Circle().strokeBorder(Palette.ember, lineWidth: 2))
                    .offset(x: position - 12)
            }
            .frame(height: 24)
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
        .frame(height: 24)
        .accessibilityValue("\(String(format: "%.2f", scale)) times the logged portion")
    }

    private func normalized(_ value: Double) -> Double {
        Curve.remap(value, stops.first ?? 0.25, stops.last ?? 3, 0, 1)
    }

    private func denormalized(_ fraction: Double) -> Double {
        (stops.first ?? 0.25) + fraction * ((stops.last ?? 3) - (stops.first ?? 0.25))
    }

    /// Pulls toward a stop when close, but doesn't prevent values in between.
    private func snap(_ value: Double) -> Double {
        guard let nearest = stops.min(by: { abs($0 - value) < abs($1 - value) }) else { return value }
        return abs(nearest - value) < 0.08 ? nearest : (value * 100).rounded() / 100
    }
}
