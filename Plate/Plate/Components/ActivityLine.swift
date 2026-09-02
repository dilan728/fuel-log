import SwiftUI

/// "Looking up chicken shawarma" — what the agent is doing, in words.
///
/// A line, not a pill. Capsules read as interactive; these are not tappable and they are
/// not content, they are the quietest possible reassurance that something is happening.
/// Once complete the marker stops moving and the line stays put, because a row that
/// vanishes makes everything below it jump.
struct ActivityLine: View {
    let activity: Activity

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Metrics.snug) {
            marker
                .frame(width: 5, height: 5)

            Text(activity.displayLabel)
                .typeStyle(.micro, activity.isComplete ? Palette.inkFaint : Palette.inkSoft)
                .contentTransition(.opacity)
                .lineLimit(1)
        }
        .plateAnimation(Motion.snap, value: activity.isComplete)
        .plateAnimation(Motion.snap, value: activity.displayLabel)
        .accessibilityLabel(activity.displayLabel)
    }

    @ViewBuilder
    private var marker: some View {
        if activity.isComplete {
            // A hairline dash rather than a checkmark: a tick is a claim of success, and
            // this is a log of what happened.
            Rectangle()
                .fill(Palette.inkGhost)
                .frame(width: 5, height: 1)
                .transition(.opacity)
        } else {
            Circle()
                .fill(Palette.ember)
                .scaleEffect(pulse ? 1 : 0.5)
                .opacity(pulse ? 1 : 0.45)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }
}

/// The run of activity above an agent message.
struct ActivityStrip: View {
    let activities: [Activity]

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tight) {
                ForEach(activities) { activity in
                    ActivityLine(activity: activity)
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: 4).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            }
            .plateAnimation(Motion.snap, value: activities.count)
        }
    }
}
