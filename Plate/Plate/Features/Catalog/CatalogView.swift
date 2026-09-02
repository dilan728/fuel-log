import SwiftUI

/// Every meal you've logged, as a magazine.
///
/// The layout is a repeating editorial rhythm rather than a uniform grid — a wide
/// hero, then a two-up, then a two-up — which is what stops a page of food photography
/// from reading as a spreadsheet of thumbnails. Sections are days, and scrolling
/// through them updates the focused day, so pinching back in returns you to whatever
/// you were just looking at.
struct CatalogView: View {
    @Environment(AppModel.self) private var app
    var namespace: Namespace.ID
    var onOpenEntry: (UUID, DayID) -> Void

    @State private var visibleDay: DayID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34, pinnedViews: [.sectionHeaders]) {
                    ForEach(app.loggedDays) { day in
                        Section {
                            DaySpread(
                                day: day,
                                namespace: namespace,
                                onOpenEntry: { onOpenEntry($0, day) }
                            )
                        } header: {
                            CatalogDayHeader(day: day, target: app.profile.calorieTarget)
                        }
                        .id(day)
                    }

                    if app.loggedDays.isEmpty {
                        CatalogEmptyState()
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .top) {
                // Reserve room for the floating top bar. Content padding is not enough:
                // pinned headers pin to the scroll view's top edge, not to the content.
                Color.clear.frame(height: 44)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Land on the day the Thread was showing rather than at the top.
                proxy.scrollTo(app.focusedDay, anchor: .top)
            }
            .onChange(of: visibleDay) { _, day in
                guard let day else { return }
                app.focus(day)
            }
        }
        // Overlays, not colour effects on the scroll view — see `SurfaceOverlays`.
        .plateFilmTreatment(grain: 0.045, vignette: 0.4)
    }
}

// MARK: - A day's spread

private struct DaySpread: View {
    let day: DayID
    var namespace: Namespace.ID
    var onOpenEntry: (UUID) -> Void

    @Environment(AppModel.self) private var app
    @State private var entries: [FoodEntry] = []

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(EditorialLayout.rows(for: entries).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { entry in
                        CatalogTile(
                            entry: entry,
                            aspect: row.count == 1 ? 1.42 : 1,
                            namespace: namespace
                        ) {
                            onOpenEntry(entry.id)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .task {
            let session = app.session(for: day)
            await session.loadIfNeeded()
            entries = session.entries
            // Fill in any photography this day is missing, now that it's on screen.
            for entry in entries {
                app.ensureImage(for: entry, on: day)
            }
        }
        .onChange(of: app.session(for: day).entries) { _, updated in
            entries = updated
        }
    }
}

/// Chunks a day's entries into an alternating wide/two-up rhythm.
enum EditorialLayout {
    static func rows(for entries: [FoodEntry]) -> [[FoodEntry]] {
        // Two items read better side by side than as two stacked heroes.
        if entries.count == 2 { return [entries] }

        var rows: [[FoodEntry]] = []
        var index = 0
        // Wide, pair, pair, wide, pair, pair… A lone trailing entry becomes a wide
        // hero rather than a half-empty row.
        let pattern = [1, 2, 2]
        var step = 0

        while index < entries.count {
            let size = pattern[step % pattern.count]
            let remaining = entries.count - index
            let take = remaining == 1 ? 1 : min(size, remaining)
            rows.append(Array(entries[index..<(index + take)]))
            index += take
            step += 1
        }
        return rows
    }
}

// MARK: - Tile

private struct CatalogTile: View {
    let entry: FoodEntry
    var aspect: CGFloat
    var namespace: Namespace.ID
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // A clear box sets the aspect ratio and the image fills it. Applying
            // `aspectRatio(_, contentMode: .fill)` to the image itself lets it overflow
            // the layout frame, and the corner clip then cuts the wrong rectangle.
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    FoodImageView(entry: entry, cornerRadius: 20)
                        .matchedGeometryEffect(id: entry.id, in: namespace)
                }
                .overlay(alignment: .bottomLeading) { caption }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(entry.name), \(Int(entry.facts.calories.rounded())) calories")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.name)
                .font(.system(size: aspect > 1.2 ? 19 : 15, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("\(Int(entry.facts.calories.rounded())) cal")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.82))
        }
        .shadow(color: .black.opacity(0.55), radius: 7, y: 1)
        .padding(.horizontal, 13)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // A scrim only where the text is, so the photograph stays a photograph.
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 96)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Section header

private struct CatalogDayHeader: View {
    let day: DayID
    let target: Double?      // reserved for a future goal indicator in the header

    @Environment(AppModel.self) private var app

    private var totals: NutritionFacts {
        app.session(for: day).totals
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.title)
                .font(.plateTitle)
                .foregroundStyle(Palette.ink)

            Spacer()

            Text("\(Int(totals.calories.rounded())) cal")
                .font(.plateCaption)
                .tracking(0.7)
                .foregroundStyle(Palette.inkFaint)

            MacroBar(facts: totals, height: 3)
                .frame(width: 44)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            // Glass, so photographs scroll under the header rather than being clipped
            // by an opaque bar.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Palette.hairline.frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .horizontal)
        }
    }
}

private struct CatalogEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet")
                .font(.plateTitle)
                .foregroundStyle(Palette.ink)
            Text("Log a few meals and they'll collect here.")
                .font(.plateBody)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}
