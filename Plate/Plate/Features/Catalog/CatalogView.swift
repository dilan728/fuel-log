import SwiftUI

/// Every meal you've logged, as a lookbook.
///
/// Captions sit *below* the photographs, in the page ground, the way a plate is captioned
/// in print. The first version laid a black scrim over the bottom of each image and set
/// the name in white on top of it — which is the single most generic treatment available,
/// and it damages the photograph to make room for text the page had space for anyway.
struct CatalogView: View {
    @Environment(AppModel.self) private var app
    var namespace: Namespace.ID
    var onOpenEntry: (UUID, DayID) -> Void

    @State private var visibleDay: DayID?

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Metrics.gutter),
         GridItem(.flexible(), spacing: Metrics.gutter)]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(app.loggedDays) { day in
                        Section {
                            DaySpread(day: day, columns: columns, namespace: namespace) {
                                onOpenEntry($0, day)
                            }
                        } header: {
                            CatalogDayHeader(day: day)
                        }
                        .id(day)
                    }

                    if app.loggedDays.isEmpty { CatalogEmptyState() }

                    Color.clear.frame(height: Metrics.vast)
                }
            }
            .safeAreaInset(edge: .top) {
                // Pinned headers pin to the scroll view's edge, not to the content, so
                // room for the floating bar has to be reserved as an inset.
                Color.clear.frame(height: 40)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(app.focusedDay, anchor: .top) }
            .onChange(of: visibleDay) { _, day in
                guard let day else { return }
                app.focus(day)
            }
        }
        // Grain only. The vignette darkened the page edges, which on a flat paper ground
        // reads as a lighting effect applied to a printed sheet.
        .overlay { GrainOverlay(intensity: 0.032) }
    }
}

// MARK: - A day's spread

private struct DaySpread: View {
    let day: DayID
    let columns: [GridItem]
    var namespace: Namespace.ID
    var onOpenEntry: (UUID) -> Void

    @Environment(AppModel.self) private var app
    @State private var entries: [FoodEntry] = []

    var body: some View {
        let spread = CatalogArrangement.spread(for: entries)

        return VStack(alignment: .leading, spacing: Metrics.roomy) {
            if let hero = spread.hero {
                CatalogPlate(entry: hero, namespace: namespace, isHero: true) {
                    onOpenEntry(hero.id)
                }
            }

            if !spread.grid.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.roomy) {
                    ForEach(spread.grid) { entry in
                        CatalogPlate(entry: entry, namespace: namespace, isHero: false) {
                            onOpenEntry(entry.id)
                        }
                    }
                }
            }
        }
        .plateMargins()
        .padding(.top, Metrics.wide)
        .padding(.bottom, Metrics.generous)
        .task {
            let session = app.session(for: day)
            await session.loadIfNeeded()
            entries = session.entries
            for entry in entries { app.ensureImage(for: entry, on: day) }
        }
        .onChange(of: app.session(for: day).entries) { _, updated in
            entries = updated
        }
    }
}

// MARK: - Plate

private struct CatalogPlate: View {
    let entry: FoodEntry
    var namespace: Namespace.ID
    var isHero: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Metrics.snug) {
                FoodImageView(entry: entry, cornerRadius: Metrics.imageRadius)
                    .matchedGeometryEffect(id: entry.id, in: namespace)
                    .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .typeStyle(isHero ? .title : .subtitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .firstTextBaseline, spacing: Metrics.snug) {
                        // Quantity only. The meal is implied by the day's running order,
                        // and carrying it here truncated the line in a two-column tile.
                        Text(entry.quantity.display)
                            .typeStyle(.micro, Palette.inkFaint)
                            .lineLimit(1)
                        Spacer(minLength: Metrics.tight)
                        Text("\(Int(entry.facts.calories.rounded()))")
                            .typeStyle(.numeric, Palette.inkSoft)
                    }
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(Int(entry.facts.calories.rounded())) calories")
    }
}

// MARK: - Section header

private struct CatalogDayHeader: View {
    let day: DayID

    @Environment(AppModel.self) private var app

    private var totals: NutritionFacts { app.session(for: day).totals }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.title)
                    .typeStyle(.title)
                    .opticalLeading(forSize: 22)
                Spacer(minLength: Metrics.step)
                Text("\(DayHeader.figure(totals.calories)) cal")
                    .typeStyle(.micro, Palette.inkFaint)
            }
            .plateMargins()
            .padding(.top, Metrics.step)
            .padding(.bottom, Metrics.snug)

            EnergyRule(facts: totals, target: app.profile.calorieTarget, thickness: 2, isAnimated: false)
                .plateMargins()
                .padding(.bottom, Metrics.snug)
        }
        .background {
            // Solid paper, not a material. A material over a warm page renders as a grey
            // band that does not match anything else on screen; a printed page simply has
            // a header, and the measure below it is border enough.
            Rectangle().fill(Palette.paper)
        }
    }
}

private struct CatalogEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.snug) {
            Text("Nothing here yet")
                .typeStyle(.title)
            Text("Log a few meals and they'll collect here.")
                .typeStyle(.body, Palette.inkFaint)
        }
        .plateMargins()
        .padding(.top, Metrics.vast)
    }
}
