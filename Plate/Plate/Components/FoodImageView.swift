import SwiftUI

/// A food's picture, whatever state it happens to be in.
///
/// There is no empty state and no spinner. The procedural plate is always drawn
/// underneath, so a card is complete the instant it appears; a generated photograph,
/// when it arrives, materialises on top of it. That ordering is what lets the app be
/// pleasant with no API keys and better with them, rather than broken without.
struct FoodImageView: View {
    let entry: FoodEntry
    var cornerRadius: CGFloat = 16

    @State private var photograph: UIImage?
    @State private var reveal: Double = 0

    private var palette: FoodPalette { .forFood(entry.name) }
    private var form: FoodForm { .infer(from: entry.name) }

    var body: some View {
        ZStack {
            ProceduralPlateView(seed: entry.imageSeed, palette: palette, form: form)
                .plateShimmer(
                    sheen: Palette.ember.opacity(0.5),
                    isActive: entry.image.isGenerating
                )

            if let photograph {
                Image(uiImage: photograph)
                    .resizable()
                    .scaledToFill()
                    .plateMaterialize(
                        progress: reveal,
                        seed: entry.imageSeed,
                        tint: Palette.ember
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
        .task(id: entry.image) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let fileName = entry.image.fileName else {
            photograph = nil
            reveal = 0
            return
        }

        // Already on screen from a previous pass — don't re-run the reveal, which
        // would make images flicker every time the list re-diffs.
        if photograph != nil, reveal >= 1 { return }

        guard let image = ImageCache.shared.image(for: fileName) else { return }
        photograph = image

        withAnimation(.easeOut(duration: Motion.materializeDuration)) {
            reveal = 1
        }
    }
}
