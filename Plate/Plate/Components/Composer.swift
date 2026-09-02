import SwiftUI

/// The input bar.
///
/// Floats over the conversation on a material, bounded by a single hairline. The first
/// version added a shader-drawn specular rim, and against a dark page it became the
/// brightest object on screen — a control announcing itself louder than the content it
/// exists to add to.
struct Composer: View {
    @Binding var text: String
    var isResponding: Bool
    var placeholder: String
    var onSend: () -> Void
    var onStop: () -> Void

    @FocusState private var isFocused: Bool
    @State private var sendScale: CGFloat = 1
    @Environment(\.displayScale) private var displayScale

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Metrics.snug) {
            TextField(placeholder, text: $text, axis: .vertical)
                .typeStyle(.body)
                .tint(Palette.ember)
                .lineLimit(1...5)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.vertical, 7)

            action
        }
        .padding(.leading, Metrics.wide)
        .padding(.trailing, Metrics.snug)
        .padding(.vertical, Metrics.snug)
        .background {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.strokeBorder(Palette.hairline, lineWidth: 1 / displayScale)
                }
        }
        .plateAnimation(Motion.snap, value: canSend)
        .plateAnimation(Motion.snap, value: isResponding)
    }

    private var action: some View {
        Button {
            if isResponding {
                onStop()
                Haptics.shared.select()
            } else {
                send()
            }
        } label: {
            ZStack {
                Circle().fill(canSend || isResponding ? Palette.ember : Palette.inkGhost)
                Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: isResponding ? 10 : 13, weight: .bold))
                    .foregroundStyle(canSend || isResponding ? Color.white : Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 32, height: 32)
            .scaleEffect(sendScale)
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !isResponding)
        .accessibilityLabel(isResponding ? "Stop" : "Send")
    }

    private func send() {
        guard canSend else { return }
        onSend()
        // A quick squash, so the send has a physical beat independent of however long
        // the reply takes to begin.
        withAnimation(.easeOut(duration: 0.08)) { sendScale = 0.84 }
        withAnimation(Motion.bounce.delay(0.08)) { sendScale = 1 }
    }
}

/// A band that fades the page out beneath a floating bar.
///
/// The one gradient in the app that earns its place: without it, text scrolls to a hard
/// stop behind the composer, and with a solid backing the composer becomes a slab.
struct FadeBand: View {
    var height: CGFloat = 64

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.paper.opacity(0), location: 0),
                .init(color: Palette.paper.opacity(0.86), location: 0.55),
                .init(color: Palette.paper, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
