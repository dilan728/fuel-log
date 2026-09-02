import SwiftUI

/// One day, as a conversation.
struct DayThreadView: View {
    @Bindable var session: ThreadSession
    let profile: UserProfile
    var namespace: Namespace.ID
    var onOpenEntry: (UUID) -> Void
    var onOpenSummary: () -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var greeting: String = ""

    /// Header collapse, driven by how far the thread has scrolled.
    private var collapse: Double {
        Curve.remap(Double(scrollOffset), 0, 90, 0, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            DayHeader(
                day: session.day,
                facts: session.totals,
                target: profile.calorieTarget,
                collapse: collapse,
                onTapRing: onOpenSummary
            )
            .background {
                // The header only earns a divider once content is behind it.
                Palette.hairline
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(collapse)
            }

            transcript
        }
        .task {
            await session.loadIfNeeded()
            greeting = SystemPrompt.greeting(day: session.day, profile: profile)
        }
    }

    private var transcript: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if session.messages.isEmpty {
                        EmptyDayView(
                            greeting: greeting,
                            day: session.day,
                            onSuggestion: { session.send($0) }
                        )
                        .padding(.top, 24)
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
                        RetryRow(message: failure) { session.retry() }
                    }

                    // Space for the composer, which floats over this scroll view.
                    Color.clear.frame(height: 92)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = max(offset, 0)
            }
        // Keeps the newest message in view as the reply streams in, without a
        // scrollTo fighting the user's own scrolling.
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
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .plateBodyStyle()
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(Palette.emberSoft)
                    }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))

        case .agent:
            VStack(alignment: .leading, spacing: 10) {
                ActivityStrip(activities: message.activity)

                if !message.text.isEmpty {
                    StreamingText(text: message.text, isStreaming: message.state.isStreaming)
                } else if message.state.isStreaming && message.activity.isEmpty {
                    ThinkingIndicator()
                }

                if !message.entryIDs.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(message.entryIDs, id: \.self) { id in
                            if let entry = session.entry(id) {
                                FoodCard(entry: entry, namespace: namespace) {
                                    onOpenEntry(id)
                                }
                                .transition(
                                    .scale(scale: 0.94, anchor: .leading)
                                    .combined(with: .opacity)
                                )
                            }
                        }
                    }
                    .plateAnimation(Motion.bounce, value: message.entryIDs.count)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .marker:
            Text(message.text)
                .plateCaptionStyle()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Three dots, before the first token lands.
private struct ThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.inkFaint)
                    .frame(width: 5, height: 5)
                    .scaleEffect(scale(for: index))
                    .opacity(0.4 + 0.6 * scale(for: index))
            }
        }
        .frame(height: 20)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityLabel("Thinking")
    }

    private func scale(for index: Int) -> Double {
        // A travelling wave rather than three independent pulses, so it reads as one
        // motion crossing the row.
        let offset = Double(index) * 0.22
        let wave = sin((phase - offset) * 2 * .pi)
        return 0.7 + 0.3 * max(wave, 0)
    }
}

private struct RetryRow: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Palette.alert)

            Text(message)
                .font(.plateLabel)
                .foregroundStyle(Palette.inkSoft)

            Spacer(minLength: 4)

            Button("Try again", action: onRetry)
                .font(.plateLabel)
                .foregroundStyle(Palette.ember)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.alert.opacity(0.07))
        }
    }
}

// MARK: - Empty day

private struct EmptyDayView: View {
    let greeting: String
    let day: DayID
    var onSuggestion: (String) -> Void

    private var suggestions: [String] {
        let hour = Calendar.current.component(.hour, from: .now)
        var items: [String]
        switch hour {
        case 4..<11: items = ["Two eggs and toast", "Oatmeal with blueberries", "Just a coffee"]
        case 11..<16: items = ["Chicken salad", "Turkey sandwich", "Leftovers from last night"]
        case 16..<22: items = ["Pasta and a glass of wine", "Salmon and rice", "Takeaway curry"]
        default: items = ["A handful of almonds", "Yogurt", "Late snack"]
        }
        if !day.isToday { items = ["Add something to this day"] + items.prefix(2) }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(greeting)
                .font(.plateTitle)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.plateLabel)
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background {
                                Capsule().fill(Palette.paperRaised)
                            }
                            .overlay {
                                Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }
}
