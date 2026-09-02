import SwiftUI

/// One day, as a conversation.
struct DayThreadView: View {
    @Bindable var session: ThreadSession
    let profile: UserProfile
    var namespace: Namespace.ID
    var onOpenEntry: (UUID) -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var greeting: String = ""

    /// Header collapse, driven by how far the thread has scrolled.
    private var collapse: Double {
        Curve.remap(Double(scrollOffset), 0, 88, 0, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            DayHeader(
                day: session.day,
                facts: session.totals,
                target: profile.calorieTarget,
                collapse: collapse
            )

            transcript
        }
        .task {
            await session.loadIfNeeded()
            greeting = SystemPrompt.greeting(day: session.day, profile: profile)
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.roomy) {
                if session.messages.isEmpty {
                    EmptyDay(greeting: greeting, day: session.day) { session.send($0) }
                        .padding(.top, Metrics.wide)
                }

                ForEach(session.messages) { message in
                    MessageRow(
                        message: message,
                        session: session,
                        namespace: namespace,
                        onOpenEntry: onOpenEntry
                    )
                    .id(message.id)
                }

                if let failure = session.failure {
                    RetryNotice(message: failure) { session.retry() }
                }

                // Room for the composer, which floats over this scroll view.
                Color.clear.frame(height: 96)
            }
            .plateMargins()
            .padding(.top, Metrics.wide)
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = max(offset, 0)
        }
        // Keeps the newest message in view as a reply streams in, without a scrollTo
        // fighting the user's own scrolling.
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }
}

// MARK: - Messages

private struct MessageRow: View {
    let message: ChatMessage
    let session: ThreadSession
    let namespace: Namespace.ID
    var onOpenEntry: (UUID) -> Void

    var body: some View {
        switch message.role {
        case .user:
            // Set as a margin note: right-aligned, ruled on the outer edge. A tinted
            // rounded rectangle is the last unmistakable "chat app" object on the page,
            // and alignment already says who is speaking.
            HStack(alignment: .top, spacing: Metrics.step) {
                Spacer(minLength: Metrics.vast)
                Text(message.text)
                    .typeStyle(.body, Palette.inkSoft)
                    .multilineTextAlignment(.trailing)
                Rectangle()
                    .fill(Palette.ember)
                    .frame(width: 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .transition(.move(edge: .bottom).combined(with: .opacity))

        case .agent:
            VStack(alignment: .leading, spacing: Metrics.step) {
                ActivityStrip(activities: message.activity)

                if !message.text.isEmpty {
                    StreamingText(text: message.text, isStreaming: message.state.isStreaming)
                } else if message.state.isStreaming && message.activity.isEmpty {
                    ThinkingIndicator()
                }

                let entries = message.entryIDs.compactMap { session.entry($0) }
                if !entries.isEmpty {
                    FoodLedger(entries: entries, namespace: namespace, onTap: onOpenEntry)
                        .padding(.top, Metrics.tight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .marker:
            Text(message.text)
                .typeStyle(.micro, Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Three dots, before the first token lands.
private struct ThinkingIndicator: View {
    @State private var phase = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.inkFaint)
                    .frame(width: 4, height: 4)
                    .scaleEffect(scale(for: index))
                    .opacity(0.35 + 0.65 * scale(for: index))
            }
        }
        .frame(height: 18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .accessibilityLabel("Thinking")
    }

    private func scale(for index: Int) -> Double {
        // A travelling wave rather than three independent pulses, so it reads as one
        // motion crossing the row.
        let wave = sin((phase - Double(index) * 0.22) * 2 * .pi)
        return 0.7 + 0.3 * max(wave, 0)
    }
}

private struct RetryNotice: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.snug) {
            Hairline(color: Palette.alert.opacity(0.35))
            HStack(alignment: .firstTextBaseline) {
                Text(message)
                    .typeStyle(.label, Palette.inkSoft)
                Spacer(minLength: Metrics.step)
                Button("Try again", action: onRetry)
                    .typeStyle(.label, Palette.ember)
            }
        }
    }
}

// MARK: - Empty day

/// The opening of a day with nothing in it.
///
/// The suggestions are set as a ruled list rather than as a row of capsules — a menu
/// card, which is both more in keeping with the page and easier to read than three pills
/// of different widths.
private struct EmptyDay: View {
    let greeting: String
    let day: DayID
    var onSuggestion: (String) -> Void

    private var suggestions: [String] {
        let hour = Calendar.current.component(.hour, from: .now)
        guard day.isToday else {
            return ["Add something to this day", "The usual", "How did this day go?"]
        }
        switch hour {
        case 4..<11:  return ["Two eggs and toast", "Oatmeal with blueberries", "Just a coffee"]
        case 11..<16: return ["Chicken salad", "Turkey sandwich", "Leftovers from last night"]
        case 16..<22: return ["Pasta and a glass of wine", "Salmon and rice", "Takeaway curry"]
        default:      return ["A handful of almonds", "Yogurt", "Late snack"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.roomy) {
            Text(greeting)
                .typeStyle(.title)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Hairline()
                    Button {
                        onSuggestion(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion).typeStyle(.body, Palette.inkSoft)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.vertical, Metrics.step)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                Hairline()
            }
        }
    }
}
