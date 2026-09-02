import SwiftUI

/// The input bar.
///
/// Floats over the conversation on glass rather than sitting in a bordered footer, so
/// the thread reads as a continuous page that the bar happens to be resting on.
struct Composer: View {
    @Binding var text: String
    var isResponding: Bool
    var placeholder: String
    var onSend: () -> Void
    var onStop: () -> Void

    @FocusState private var isFocused: Bool
    @State private var sendButtonScale: CGFloat = 1

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .plateBodyStyle()
                .foregroundStyle(Palette.ink)
                .tint(Palette.ember)
                .lineLimit(1...5)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.leading, 6)
                .padding(.vertical, 7)

            actionButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(GlassSurface(cornerRadius: 25, thickness: 16))
        .plateAnimation(Motion.snap, value: canSend)
        .plateAnimation(Motion.snap, value: isResponding)
    }

    @ViewBuilder
    private var actionButton: some View {
        Button {
            if isResponding {
                onStop()
                Haptics.shared.select()
            } else {
                send()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(canSend || isResponding ? Palette.ember : Palette.inkGhost)

                Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: isResponding ? 11 : 14, weight: .bold))
                    .foregroundStyle(canSend || isResponding ? Color.white : Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)
            .scaleEffect(sendButtonScale)
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !isResponding)
        .accessibilityLabel(isResponding ? "Stop" : "Send")
    }

    private func send() {
        guard canSend else { return }
        onSend()
        // A quick squash on the button so the send has a physical beat, independent of
        // however long the reply takes to start.
        withAnimation(.easeOut(duration: 0.09)) { sendButtonScale = 0.86 }
        withAnimation(Motion.bounce.delay(0.09)) { sendButtonScale = 1 }
    }
}
