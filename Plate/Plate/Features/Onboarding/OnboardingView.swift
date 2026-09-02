import SwiftUI

/// First run.
///
/// Three questions, all skippable, and none of them a form. The app works completely
/// without any of the answers — this exists to make the first day feel addressed to
/// someone rather than to a user, and to let the ring mean something from the start.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var name = ""
    @State private var target: Double?
    @FocusState private var isNameFocused: Bool

    private let targets: [Double?] = [1600, 1800, 2000, 2200, 2500, nil]

    var body: some View {
        ZStack {
            backdrop

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: nameStep
                    default: targetStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 26).combined(with: .opacity),
                        removal: .offset(y: -20).combined(with: .opacity)
                    )
                )

                Spacer(minLength: 0)

                controls
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 34)
        }
        .plateAnimation(Motion.glide, value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plate")
                .font(.system(size: 56, weight: .regular, design: .serif))
                .foregroundStyle(Palette.ink)

            Text("A food journal you talk to.\nTell it what you ate; it does the rest.")
                .font(.plateBody)
                .lineSpacing(6)
                .foregroundStyle(Palette.inkSoft)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What should I call you?")
                .font(.plateTitle)
                .foregroundStyle(Palette.ink)

            TextField("Your name", text: $name)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Palette.ink)
                .tint(Palette.ember)
                .textContentType(.givenName)
                .submitLabel(.next)
                .focused($isNameFocused)
                .onSubmit { advance() }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
        .onAppear { isNameFocused = true }
    }

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Aiming for a daily number?")
                .font(.plateTitle)
                .foregroundStyle(Palette.ink)

            Text("This turns the ring into a goal. You can skip it — plenty of people just want the record.")
                .font(.plateBody)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            FlowRow(spacing: 8) {
                ForEach(Array(targets.enumerated()), id: \.offset) { _, value in
                    let isSelected = target == value
                    Button {
                        Haptics.shared.select()
                        withAnimation(Motion.snap) { target = value }
                    } label: {
                        Text(value.map { "\(Int($0))" } ?? "No target")
                            .font(.plateLabel)
                            .foregroundStyle(isSelected ? Color.white : Palette.inkSoft)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background {
                                Capsule().fill(isSelected ? Palette.ember : Palette.paperRaised)
                            }
                            .overlay {
                                Capsule().strokeBorder(
                                    isSelected ? .clear : Palette.hairline,
                                    lineWidth: 0.5
                                )
                            }
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    // MARK: Chrome

    private var controls: some View {
        HStack(spacing: 14) {
            if step > 0 {
                Button("Back") {
                    Haptics.shared.select()
                    withAnimation(Motion.glide) { step -= 1 }
                }
                .font(.plateLabel)
                .foregroundStyle(Palette.inkFaint)
                .transition(.opacity)
            }

            Spacer()

            Button(step == 2 ? "Start" : "Continue") { advance() }
                .font(.plateLabel)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 46)
                .background(Capsule().fill(Palette.ember))
                .buttonStyle(PressableCardStyle())
        }
    }

    /// Three procedural plates, drifting. Doubles as an honest preview of what the
    /// Catalog looks like before there is anything in it.
    private var backdrop: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSince(PlateShaders.epoch)
                ZStack {
                    plate("Pesto Pasta", at: CGPoint(x: 0.18, y: 0.20), size: 150, phase: t * 0.11)
                    plate("Blueberry Yogurt", at: CGPoint(x: 0.86, y: 0.34), size: 116, phase: t * 0.09 + 2)
                    plate("Flat White", at: CGPoint(x: 0.30, y: 0.80), size: 96, phase: t * 0.13 + 4)
                }
            }
            .ignoresSafeArea()
            .opacity(0.5)
            .blur(radius: 0.4)
        }
    }

    private func plate(_ food: String, at unit: CGPoint, size: CGFloat, phase: Double) -> some View {
        GeometryReader { proxy in
            ProceduralPlateView(food: food)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .position(
                    x: proxy.size.width * unit.x + CGFloat(cos(phase)) * 12,
                    y: proxy.size.height * unit.y + CGFloat(sin(phase * 1.3)) * 14
                )
        }
    }

    // MARK: Flow

    private func advance() {
        Haptics.shared.commit()
        guard step == 2 else {
            withAnimation(Motion.glide) { step += 1 }
            return
        }

        isNameFocused = false
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = target
        Task {
            await app.saveProfile { profile in
                profile.name = name.isEmpty ? nil : name
                profile.calorieTarget = target
                profile.hasCompletedOnboarding = true
            }
            dismiss()
        }
    }
}

/// A wrapping row. `LazyVGrid` cannot do intrinsic-width wrapping, and the target
/// chips are all different widths.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, in: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var range: Range<Int>
        var y: CGFloat
        var height: CGFloat
        var width: CGFloat
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var start = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append(Row(range: start..<index, y: y, height: rowHeight, width: x - spacing))
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
                start = index
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        if start < subviews.count {
            rows.append(Row(range: start..<subviews.count, y: y, height: rowHeight, width: x - spacing))
        }
        return rows
    }
}
