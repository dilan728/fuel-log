import Foundation

/// How a day's meals are laid out in the catalog.
///
/// The day's first meal runs full width; the rest fall into a two-column grid. One
/// special case is enough to give the page a rhythm — the previous version alternated a
/// wide/pair/pair pattern and the result read as arbitrary, because nothing about the
/// third meal of a day justifies it being wide.
///
/// Extracted from the view so the invariant that matters — every meal appears exactly
/// once, in order — can be tested without a renderer.
enum CatalogArrangement {
    struct Spread: Equatable {
        var hero: FoodEntry?
        var grid: [FoodEntry]

        var all: [FoodEntry] { (hero.map { [$0] } ?? []) + grid }
    }

    static func spread(for entries: [FoodEntry]) -> Spread {
        guard let first = entries.first else { return Spread(hero: nil, grid: []) }
        return Spread(hero: first, grid: Array(entries.dropFirst()))
    }
}
