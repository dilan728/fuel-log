import SwiftUI

/// "Looking up chicken shawarma" — what the agent is doing, in words.
///
/// Deliberately small and low-contrast. It is reassurance that something is happening,
/// not content; once complete it stops moving and recedes rather than disappearing,
/// because a row that vanishes makes the message below it jump.
struct ActivityChip: View {
    let activity: Activity

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            icon
                .frame(width: 11, height: 11)

            Text(activity.displayLabel)
                .font(.plateLabel)
                .foregroundStyle(activity.isComplete ? Palette.inkFaint : Palette.inkSoft)
                .contentTransition(.opacity)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(activity.isComplete ? Palette.inkGhost.opacity(0.35) : Palette.emberSoft)
        }
        .plateAnimation(Motion.snap, value: activity.isComplete)
        .plateAnimation(Motion.snap, value: activity.displayLabel)
        .accessibilityLabel(activity.displayLabel)
    }

    @ViewBuilder
    private var icon: some View {
        if activity.isComplete {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.inkFaint)
                .transition(.scale.combined(with: .opacity))
        } else {
            // A slow breathing dot rather than a spinner: a spinner implies waiting,
            // and most of these complete in well under a second.
            Circle()
                .fill(Palette.ember)
                .scaleEffect(pulse ? 1 : 0.55)
                .opacity(pulse ? 1 : 0.5)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }
}

/// The row of chips above an agent message.
struct ActivityStrip: View {
    let activities: [Activity]

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(activities) { activity in
                    ActivityChip(activity: activity)
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: 6).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            }
            .plateAnimation(Motion.snap, value: activities.count)
        }
    }
}
