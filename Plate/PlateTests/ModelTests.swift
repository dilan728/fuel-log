import XCTest
import SwiftUI
import UIKit
@testable import Plate

final class QuantityTests: XCTestCase {

    func testTightUnitsHaveNoSpace() {
        XCTAssertEqual(Quantity(amount: 200, unit: .gram).display, "200g")
        XCTAssertEqual(Quantity(amount: 6, unit: .ounce).display, "6oz")
    }

    func testPluralisation() {
        XCTAssertEqual(Quantity(amount: 1, unit: .slice).display, "1 slice")
        XCTAssertEqual(Quantity(amount: 3, unit: .slice).display, "3 slices")
    }

    func testBareCountsAreMarked() {
        // "2 · Breakfast" scans as a row number; "×2 · Breakfast" scans as an amount.
        XCTAssertEqual(Quantity(amount: 2, unit: .piece).display, "×2")
        XCTAssertEqual(Quantity(amount: 1, unit: .piece).display, "")
    }

    func testFractionsRenderAsPeopleSayThem() {
        XCTAssertEqual(Quantity(amount: 0.5, unit: .cup).display, "½ cups")
        XCTAssertEqual(Quantity(amount: 1.5, unit: .cup).display, "1½ cups")
        XCTAssertEqual(Quantity(amount: 0.25, unit: .cup).display, "¼ cups")
    }

    func testSubtitleOmitsTheSeparatorWhenThereIsNoQuantity() {
        let entry = FoodEntry(
            name: "Coffee",
            quantity: Quantity(amount: 1, unit: .piece),
            facts: .zero,
            meal: .breakfast
        )
        XCTAssertEqual(entry.subtitle, "Breakfast")
    }
}

final class NutritionFactsTests: XCTestCase {

    func testScalingTouchesEveryField() {
        let facts = NutritionFacts(calories: 100, protein: 10, carbs: 20, fat: 5, fiber: 2, sodium: 300)
        let doubled = facts.scaled(by: 2)
        XCTAssertEqual(doubled.calories, 200)
        XCTAssertEqual(doubled.protein, 20)
        XCTAssertEqual(doubled.fiber, 4)
        XCTAssertEqual(doubled.sodium, 600)
    }

    func testAdditionKeepsOptionalsNilOnlyWhenBothAreNil() {
        let withFiber = NutritionFacts(calories: 1, protein: 0, carbs: 0, fat: 0, fiber: 3)
        let withoutFiber = NutritionFacts(calories: 1, protein: 0, carbs: 0, fat: 0)
        XCTAssertEqual((withFiber + withoutFiber).fiber, 3)
        XCTAssertNil((withoutFiber + withoutFiber).fiber)
    }

    func testEnergySplitUsesAtwaterFactorsAndSumsToOne() {
        let facts = NutritionFacts(calories: 500, protein: 25, carbs: 50, fat: 20)
        let split = facts.energySplit
        XCTAssertEqual(split.protein + split.carbs + split.fat, 1, accuracy: 0.0001)
        // Fat is 180 of 480 macro-calories.
        XCTAssertEqual(split.fat, 180.0 / 480.0, accuracy: 0.0001)
    }

    func testEnergySplitOfNothingIsZeroRatherThanNaN() {
        let split = NutritionFacts.zero.energySplit
        XCTAssertEqual(split.protein, 0)
        XCTAssertEqual(split.carbs, 0)
        XCTAssertEqual(split.fat, 0)
    }
}

final class DayIDTests: XCTestCase {

    func testRoundTripsThroughDate() {
        let day = DayID(year: 2026, month: 2, day: 28)
        XCTAssertEqual(DayID(day.date()), day)
    }

    func testAdvancingCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(DayID(year: 2026, month: 1, day: 31).advanced(by: 1), DayID(year: 2026, month: 2, day: 1))
        XCTAssertEqual(DayID(year: 2026, month: 12, day: 31).advanced(by: 1), DayID(year: 2027, month: 1, day: 1))
        XCTAssertEqual(DayID(year: 2026, month: 3, day: 1).advanced(by: -1), DayID(year: 2026, month: 2, day: 28))
    }

    func testLeapDay() {
        XCTAssertEqual(DayID(year: 2028, month: 2, day: 28).advanced(by: 1), DayID(year: 2028, month: 2, day: 29))
    }

    func testDistanceIsSignedAndSymmetric() {
        let a = DayID(year: 2026, month: 5, day: 1)
        let b = DayID(year: 2026, month: 5, day: 11)
        XCTAssertEqual(a.distance(to: b), 10)
        XCTAssertEqual(b.distance(to: a), -10)
    }

    func testRepresentativeInstantSurvivesADSTTransition() {
        // Using midnight as a day's representative instant is the classic way this
        // breaks: in some zones midnight does not exist on a spring-forward date.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        let day = DayID(year: 2018, month: 11, day: 4)
        let instant = day.date(calendar: calendar)
        XCTAssertEqual(DayID(instant, calendar: calendar), day)
    }

    func testSortsChronologically() {
        let days = [
            DayID(year: 2026, month: 1, day: 2),
            DayID(year: 2025, month: 12, day: 31),
            DayID(year: 2026, month: 1, day: 10)
        ].sorted()
        XCTAssertEqual(days.map(\.description), ["2025-12-31", "2026-01-02", "2026-01-10"])
    }

    func testDescriptionIsZeroPaddedAndSortable() {
        XCTAssertEqual(DayID(year: 2026, month: 3, day: 7).description, "2026-03-07")
    }
}

final class MealSlotTests: XCTestCase {

    func testInferenceFromTheClock() {
        func slot(atHour hour: Int) -> MealSlot {
            var components = DateComponents()
            components.year = 2026
            components.month = 6
            components.day = 1
            components.hour = hour
            return MealSlot.inferred(from: Calendar.current.date(from: components)!)
        }
        XCTAssertEqual(slot(atHour: 8), .breakfast)
        XCTAssertEqual(slot(atHour: 13), .lunch)
        XCTAssertEqual(slot(atHour: 19), .dinner)
        XCTAssertEqual(slot(atHour: 2), .snack)
    }

    func testSnacksSortLast() {
        XCTAssertEqual(
            [MealSlot.snack, .dinner, .breakfast, .lunch].sorted(),
            [.breakfast, .lunch, .dinner, .snack]
        )
    }
}

final class SeedStabilityTests: XCTestCase {

    func testFoodSeedIsStableAndCaseInsensitive() {
        // Must not use `hashValue`, which is salted per launch — a changing seed would
        // redraw every procedural plate on every app start.
        XCTAssertEqual(FoodEntry.seed(for: "Chicken Shawarma"), FoodEntry.seed(for: "chicken shawarma"))
        XCTAssertEqual(FoodEntry.seed(for: "Egg"), FoodEntry.seed(for: "Egg"))
        XCTAssertNotEqual(FoodEntry.seed(for: "Egg"), FoodEntry.seed(for: "Eggs"))
        // Distinct across a decent sample: collisions would make two different foods
        // draw identically.
        let names = NutritionDatabase.shared.records.map { FoodEntry.seed(for: $0.name) }
        XCTAssertEqual(Set(names).count, names.count, "seed collision across the food table")
    }

    func testImageCacheKeyIsStableAndFileSafe() {
        let key = ImageCache.key(forFood: "Chicken Shawarma Bowl!")
        XCTAssertEqual(key, ImageCache.key(forFood: "chicken shawarma bowl!"))
        XCTAssertTrue(key.hasSuffix(".jpg"))
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains(" "))
    }
}

final class FoodFormTests: XCTestCase {

    func testDrinksAreGlasses() {
        XCTAssertEqual(FoodForm.infer(from: "Flat White"), .glass)
        XCTAssertEqual(FoodForm.infer(from: "Orange Juice"), .glass)
        XCTAssertEqual(FoodForm.infer(from: "Red Wine"), .glass)
    }

    func testBowlFoods() {
        XCTAssertEqual(FoodForm.infer(from: "Oatmeal with Banana"), .bowl)
        XCTAssertEqual(FoodForm.infer(from: "Ramen"), .bowl)
        XCTAssertEqual(FoodForm.infer(from: "Caesar Salad"), .bowl)
    }

    func testPlateIsTheDefault() {
        XCTAssertEqual(FoodForm.infer(from: "Steak and Chips"), .plate)
        XCTAssertEqual(FoodForm.infer(from: "Margherita Pizza"), .plate)
    }

    func testLongerMatchWins() {
        // "Iced Coffee" contains no bowl word, but the point of the rule is that a
        // drink word never loses to an incidental bowl word.
        XCTAssertEqual(FoodForm.infer(from: "Iced Coffee"), .glass)
        XCTAssertEqual(FoodForm.infer(from: "Smoothie Bowl"), .glass)
    }
}

final class CatalogArrangementTests: XCTestCase {

    private func entries(_ count: Int) -> [FoodEntry] {
        (0..<count).map { FoodEntry(name: "Food \($0)", facts: .zero, meal: .lunch) }
    }

    func testEveryEntryAppearsExactlyOnceInOrder() {
        for count in 0...12 {
            let source = entries(count)
            let spread = CatalogArrangement.spread(for: source)
            XCTAssertEqual(spread.all.map(\.id), source.map(\.id), "count \(count)")
        }
    }

    func testFirstMealIsTheHero() {
        let source = entries(4)
        let spread = CatalogArrangement.spread(for: source)
        XCTAssertEqual(spread.hero?.id, source.first?.id)
        XCTAssertEqual(spread.grid.count, 3)
    }

    func testSingleMealHasNoGrid() {
        let spread = CatalogArrangement.spread(for: entries(1))
        XCTAssertNotNil(spread.hero)
        XCTAssertTrue(spread.grid.isEmpty)
    }

    func testEmptyDayHasNothing() {
        let spread = CatalogArrangement.spread(for: [])
        XCTAssertNil(spread.hero)
        XCTAssertTrue(spread.grid.isEmpty)
    }
}

final class KeywordMatchTests: XCTestCase {

    func testWholeWordsOnly() {
        // "s-TEA-k" contains "tea", and plain `contains` served steak in a glass.
        XCTAssertNil(KeywordMatch.score("tea", in: .init("Steak and Chips")))
        XCTAssertNotNil(KeywordMatch.score("tea", in: .init("Green Tea")))
    }

    func testPhrasesMatchAcrossWords() {
        XCTAssertNotNil(KeywordMatch.score("flat white", in: .init("Large Flat White")))
    }

    func testHeadNounOutranksALongerWordLater() {
        // The dish is a steak dish, even though "potato" is the longer word.
        let context = KeywordMatch.Context("Steak and Roast Potatoes")
        let steak = KeywordMatch.score("steak", in: context) ?? 0
        let potato = KeywordMatch.score("potato", in: context) ?? 0
        XCTAssertGreaterThan(steak, potato)
    }

    func testLongerPhraseStillWinsWhenNeitherLeads() {
        let context = KeywordMatch.Context("Slow Cooked Chicken Tikka Masala")
        let tikka = KeywordMatch.score("chicken tikka masala", in: context) ?? 0
        let chicken = KeywordMatch.score("chicken", in: context) ?? 0
        XCTAssertGreaterThan(tikka, chicken)
    }
}

final class FoodTextureTests: XCTestCase {

    func testShapesAreDistinguished() {
        XCTAssertEqual(FoodTexture.infer(from: "White Rice"), .grains)
        XCTAssertEqual(FoodTexture.infer(from: "Caesar Salad"), .leaves)
        XCTAssertEqual(FoodTexture.infer(from: "Avocado Toast"), .topped)
        XCTAssertEqual(FoodTexture.infer(from: "Dark Chocolate"), .slab)
        XCTAssertEqual(FoodTexture.infer(from: "Flat White"), .liquid)
    }

    func testUnknownFoodIsAPile() {
        XCTAssertEqual(FoodTexture.infer(from: "Grandmother's Casserole"), .chunks)
    }

    func testEveryTextureHasSaneRenderParameters() {
        for texture in FoodTexture.allCases {
            XCTAssertTrue((0...1).contains(Double(texture.roughness)), "\(texture)")
            XCTAssertTrue((0...1).contains(Double(texture.subsurface)), "\(texture)")
            // The shader loops to a fixed bound; exceeding it would silently drop pieces.
            XCTAssertLessThanOrEqual(texture.pieceCount, 24, "\(texture)")
        }
    }
}

final class FoodPaletteTests: XCTestCase {

    func testNoKeywordAppearsInTwoRows() {
        // Two rows claiming the same word score identically, and the winner is decided
        // by declaration order — invisible at the call site and impossible to reason
        // about. "ramen" was in both the pale-starch row and the broth row, so a bowl of
        // ramen rendered as a bowl of milk.
        var seen: [String: Int] = [:]
        for (index, keys) in FoodPalette.vocabulary.enumerated() {
            for key in keys {
                if let first = seen[key] {
                    XCTFail("'\(key)' appears in palette rows \(first) and \(index)")
                }
                seen[key] = index
            }
        }
    }

    func testCommonDishesGetTheColourYouWouldExpect() {
        // Not a colour-match test — just that the classification lands in the right
        // family, which is what a keyword table can actually promise.
        func isDarker(_ name: String, than other: String) -> Bool {
            func luminance(_ food: String) -> CGFloat {
                let resolved = UIColor(FoodPalette.forFood(food).primary)
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
                return 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
            return luminance(name) < luminance(other)
        }
        XCTAssertTrue(isDarker("Espresso", than: "Flat White"), "milk coffee should be lighter than espresso")
        XCTAssertTrue(isDarker("Dark Chocolate", than: "Banana"))
    }

    func testEveryDatabaseFoodClassifiesWithoutFallingOver() {
        for record in NutritionDatabase.shared.records {
            let recipe = FoodSceneRecipe(food: record.name)
            XCTAssertTrue(FoodForm.allCases.contains(recipe.vessel), record.name)
            XCTAssertTrue(FoodTexture.allCases.contains(recipe.texture), record.name)
            // Linear-light colours, so anything at or beyond 1 would clip on tonemap.
            for channel in [recipe.primary, recipe.secondary, recipe.base] {
                XCTAssertTrue((0...1).contains(channel.x), record.name)
                XCTAssertTrue((0...1).contains(channel.y), record.name)
                XCTAssertTrue((0...1).contains(channel.z), record.name)
            }
        }
    }
}
