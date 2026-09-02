import SwiftUI

/// A food image drawn entirely on the GPU from a seed.
///
/// This is the app's floor, not its fallback: with no API keys configured at all,
/// every entry in the Catalog still has a distinct, consistently-lit image. When a
/// generated photograph does arrive it replaces this, and the two share the same
/// studio ground so the transition doesn't shift the page's colour.
struct ProceduralPlateView: View {
    let seed: UInt32
    let palette: FoodPalette

    init(seed: UInt32, palette: FoodPalette) {
        self.seed = seed
        self.palette = palette
    }

    init(food name: String, seed: UInt32? = nil) {
        self.seed = seed ?? FoodEntry.seed(for: name)
        self.palette = .forFood(name)
    }

    var body: some View {
        // The colorEffect only reads `color.a`, so an opaque white source gives the
        // shader a full-coverage canvas to paint into.
        Rectangle()
            .fill(.white)
            .visualEffect { content, proxy in
                content.colorEffect(
                    PlateShaders.proceduralPlate(
                        size: proxy.size,
                        seed: seed,
                        hueA: palette.primary,
                        hueB: palette.secondary,
                        ground: palette.ground
                    )
                )
            }
            .accessibilityHidden(true)
    }
}

#Preview("Procedural plates") {
    let foods = ["Pesto Pasta", "Cheeseburger", "Blueberry Yogurt", "Chicken Shawarma Bowl",
                 "Caesar Salad", "Sweet Potato Curry"]
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(foods, id: \.self) { food in
                VStack(alignment: .leading, spacing: 6) {
                    ProceduralPlateView(food: food)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(food).font(.plateTitleSmall).foregroundStyle(Palette.ink)
                }
            }
        }
        .padding(16)
    }
    .background(Palette.paper)
}
