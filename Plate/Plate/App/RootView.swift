import SwiftUI

/// TEMPORARY: a smoke screen that exercises the shader stack end to end so the
/// build, the Metal library, and every shader signature are verified before the real
/// surfaces are built on top of them. Replaced by the Thread/Catalog root shortly.
struct RootView: View {
    private let foods = [
        "Pesto Pasta", "Cheeseburger", "Blueberry Yogurt",
        "Chicken Shawarma Bowl", "Caesar Salad", "Sweet Potato Curry"
    ]

    @State private var materializeProgress: Double = 0
    @State private var warp: Double = 0

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("Plate")
                        .font(.plateDisplay)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 40)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(Array(foods.enumerated()), id: \.offset) { index, food in
                            VStack(alignment: .leading, spacing: 8) {
                                ProceduralPlateView(food: food)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .plateMaterialize(
                                        progress: index == 0 ? materializeProgress : 1,
                                        seed: FoodEntry.seed(for: food),
                                        tint: Palette.ember
                                    )
                                Text(food)
                                    .font(.plateTitleSmall)
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Text("Shimmer while generating")
                        .plateCaptionStyle()
                    ProceduralPlateView(food: "Ramen")
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .plateShimmer(sheen: .white)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 140)
            }
            .plateVignette(strength: 0.35)
            .platePinchWarp(amount: warp)

            VStack {
                Spacer()
                HStack(spacing: 14) {
                    Text("1,847")
                        .font(.plateTitle)
                        .foregroundStyle(Palette.ink)
                    Text("kcal").plateCaptionStyle()
                    Spacer()
                    Button("Warp") {
                        withAnimation(Motion.glide) { warp = warp == 0 ? -0.9 : 0 }
                    }
                    .font(.plateLabel)
                    .foregroundStyle(Palette.ember)
                }
                .glassBackground(cornerRadius: 26)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .plateGrain(intensity: 0.05)
        .task {
            withAnimation(.easeOut(duration: Motion.materializeDuration)) {
                materializeProgress = 1
            }
        }
    }
}

#Preview { RootView() }
