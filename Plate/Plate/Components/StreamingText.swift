import SwiftUI

/// Text that arrives.
///
/// Built on `TextRenderer` rather than on a shader over the whole block, because the
/// interesting unit here is the *glyph*: each one fades up, rises a couple of points,
/// unblurs, and passes through a brief ember tint as the write head goes by. A shader
/// can only see pixels and would have to guess where the head is.
///
/// The wave is driven in glyph units by a single animated `progress` that chases the
/// character count, which means it stays smooth regardless of how lumpy the network
/// delivery is — a 40-character burst still reads as typing rather than as a paste.
struct StreamingText: View {
    let text: String
    var isStreaming: Bool
    var color: Color = Palette.ink

    /// How many glyphs the arrival wave spans. Wider reads as softer.
    private let rampWidth: Double = 14

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .plateBodyStyle()
            .foregroundStyle(color)
            .textRenderer(
                ArrivalRenderer(
                    progress: shouldAnimate ? progress : .greatestFiniteMagnitude,
                    rampWidth: rampWidth,
                    tint: Palette.ember
                )
            )
            .onChange(of: text.count, initial: true) { _, count in
                guard shouldAnimate else { return }
                // Linear, because this is standing in for the pace of speech; a spring
                // here makes fast passages lurch.
                withAnimation(.linear(duration: 0.22)) {
                    progress = Double(count)
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                // When the turn ends, settle everything still mid-flight.
                if !streaming {
                    withAnimation(Motion.snap) { progress = Double(text.count) + rampWidth }
                }
            }
    }

    private var shouldAnimate: Bool { isStreaming && !reduceMotion }
}

/// Draws each glyph according to how long ago the write head passed it.
private struct ArrivalRenderer: TextRenderer, Animatable {
    /// Position of the write head, in glyphs.
    var progress: Double
    var rampWidth: Double
    var tint: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // Everything settled: draw the whole thing in one pass. This is the common
        // case for every message on screen except the one being written, so it is
        // worth short-circuiting rather than walking glyphs for all of them.
        guard progress.isFinite else {
            for line in layout {
                context.draw(line)
            }
            return
        }

        var index = 0.0
        for line in layout {
            for run in line {
                for glyph in run {
                    defer { index += 1 }

                    let arrival = (progress - index) / rampWidth
                    if arrival <= 0 { continue }              // not yet written
                    if arrival >= 1 {
                        context.draw(glyph)                    // fully settled
                        continue
                    }

                    let eased = Curve.easeOut(arrival)
                    var glyphContext = context

                    // Rise into place, unblur, and fade up together.
                    glyphContext.translateBy(x: 0, y: (1 - eased) * 5)
                    glyphContext.opacity = eased
                    glyphContext.addFilter(.blur(radius: (1 - eased) * 2.2))
                    glyphContext.draw(glyph)

                    // A brief ember flash riding the head, strongest at the moment of
                    // arrival and gone within a few glyphs.
                    let flash = sin(eased * .pi)
                    if flash > 0.02 {
                        var tintContext = context
                        tintContext.translateBy(x: 0, y: (1 - eased) * 5)
                        tintContext.opacity = flash * 0.55
                        tintContext.addFilter(.blur(radius: 1.5 + (1 - eased) * 3))
                        tintContext.addFilter(.colorMultiply(tint))
                        tintContext.draw(glyph)
                    }
                }
            }
        }
    }
}

#Preview {
    StreamingPreview()
}

private struct StreamingPreview: View {
    private let full = "Got it — two eggs, toast and a black coffee. That's 320 calories to start the day."
    @State private var shown = ""

    var body: some View {
        VStack(alignment: .leading) {
            StreamingText(text: shown, isStreaming: shown.count < full.count)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .task {
            for character in full {
                shown.append(character)
                try? await Task.sleep(for: .milliseconds(28))
            }
        }
    }
}
