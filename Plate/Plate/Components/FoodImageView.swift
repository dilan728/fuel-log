import SwiftUI

/// A food's picture.
///
/// Every entry has one: either a generated photograph or a locally path-marched render
/// of the same dish. Both arrive as a cached JPEG, so this view has exactly one job —
/// show the image, and show something calm while it is being made.
struct FoodImageView: View {
    let entry: FoodEntry
    var cornerRadius: CGFloat = 4
    /// How far into the plate to crop. 1 shows the whole composition, which is right at
    /// catalog size; a 52pt thumbnail of an overhead white plate on a pale backdrop is
    /// almost entirely empty plate, so rows crop in on the food itself.
    var zoom: CGFloat = 1

    @State private var photograph: UIImage?
    @State private var reveal: Double = 0

    private var palette: FoodPalette { .forFood(entry.name) }

    var body: some View {
        ZStack {
            // The placeholder is the studio backdrop the render will land on, tinted a
            // fraction toward the dish — so the tile never changes colour temperature
            // when the image arrives, only gains detail.
            Rectangle()
                .fill(FoodPalette.studioGround)
                .overlay {
                    Rectangle().fill(palette.primary.opacity(0.07))
                }
                .plateShimmer(
                    sheen: Palette.ember.opacity(0.34),
                    isActive: photograph == nil
                )

            if let photograph {
                Image(uiImage: photograph)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(zoom)
                    .plateMaterialize(
                        progress: reveal,
                        seed: entry.imageSeed,
                        tint: Palette.ember
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: entry.image) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let fileName = entry.image.fileName else {
            photograph = nil
            reveal = 0
            return
        }
        // Already on screen from a previous pass — don't re-run the reveal, which would
        // make images flicker every time the list re-diffs.
        if photograph != nil, reveal >= 1 { return }
        guard let image = ImageCache.shared.image(for: fileName) else { return }

        photograph = image
        withAnimation(.easeOut(duration: Motion.materializeDuration)) { reveal = 1 }
    }
}

/// A rendered dish for somewhere that has no `FoodEntry` behind it — the onboarding
/// backdrop, previews. Renders on demand and caches like everything else.
struct RenderedFoodView: View {
    let name: String
    var cornerRadius: CGFloat = 0

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(FoodPalette.studioGround)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            let rendered = await FoodImageService.shared.renderedImage(forFood: name)
            withAnimation(.easeOut(duration: 0.5)) { image = rendered }
        }
        .accessibilityHidden(true)
    }
}
