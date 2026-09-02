import XCTest
@testable import Plate

/// The failure that matters for lookup is not "found nothing" — it is "confidently
/// found the wrong food". Most of these tests are about the second kind.
final class NutritionDatabaseTests: XCTestCase {
    private let database = NutritionDatabase.shared

    func testExactNameIsAPerfectMatch() {
        let match = try? XCTUnwrap(database.search("Chicken Breast", limit: 1).first)
        XCTAssertEqual(match?.record.name, "Chicken Breast")
        XCTAssertEqual(match?.score ?? 0, 1.0, accuracy: 0.0001)
    }

    func testAliasResolves() {
        XCTAssertEqual(database.bestMatch("mince")?.record.name, "Ground Beef")
        XCTAssertEqual(database.bestMatch("courgette")?.record.name, "Zucchini")
        XCTAssertEqual(database.bestMatch("crisps")?.record.name, "Chips")
    }

    func testCaseAndPunctuationAreIgnored() {
        XCTAssertEqual(database.bestMatch("GREEK YOGURT")?.record.name, "Greek Yogurt")
        XCTAssertEqual(database.bestMatch("greek-yogurt!")?.record.name, "Greek Yogurt")
    }

    func testFillerWordsAreStripped() {
        XCTAssertEqual(database.bestMatch("a bowl of the oatmeal")?.record.name, "Oatmeal")
    }

    func testTypoStillResolves() {
        XCTAssertEqual(database.bestMatch("brocoli")?.record.name, "Broccoli")   // dropped letter
        XCTAssertEqual(database.bestMatch("avacado")?.record.name, "Avocado")    // substitution
        XCTAssertEqual(database.bestMatch("yoghurt")?.record.name, "Yogurt")     // spelling variant
        XCTAssertEqual(database.bestMatch("bananna")?.record.name, "Banana")     // doubled letter
    }

    func testTwoTyposIsTooFarToApplyConfidently() {
        // One typo should resolve; two should surface as a suggestion at most, because
        // silently logging the wrong food is worse than asking.
        XCTAssertNil(database.bestMatch("avxcxdo"))
    }

    func testShorterNameWinsTies() {
        // "egg" should not resolve to "Scrambled Eggs" just because that row also
        // contains the word.
        XCTAssertEqual(database.bestMatch("egg")?.record.name, "Egg")
    }

    func testSharedWordAloneIsNotAConfidentMatch() {
        // "chicken" appears in several rows; a query that is only a shared token must
        // not clear the confidence bar on the strength of the overlap alone.
        let overlapOnly = database.search("chicken tikka biryani platter", limit: 1).first
        if let overlapOnly, overlapOnly.score >= NutritionDatabase.confidentThreshold {
            // If it is confident, it must be because it genuinely matched a dish name,
            // not because it shares one word.
            XCTAssertTrue(
                overlapOnly.record.name.lowercased().contains("tikka")
                    || overlapOnly.record.name.lowercased().contains("biryani"),
                "Confidently matched \(overlapOnly.record.name) on a shared word"
            )
        }
    }

    func testNonsenseHasNoConfidentMatch() {
        XCTAssertNil(database.bestMatch("zzzqqxwv"))
        XCTAssertNil(database.bestMatch("blorptangle surprise"))
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(database.search("").isEmpty)
        XCTAssertTrue(database.search("   ").isEmpty)
    }

    func testEveryRowParsed() {
        // Guards the table format: a malformed line is silently skipped by the parser,
        // so a count assertion is the only thing that catches it.
        XCTAssertGreaterThan(database.records.count, 190)
        for record in database.records {
            XCTAssertFalse(record.name.isEmpty)
            XCTAssertGreaterThan(record.serving.amount, 0)
            XCTAssertGreaterThan(record.servingGrams, 0)
            XCTAssertGreaterThanOrEqual(record.factsPerServing.calories, 0)
        }
    }

    func testMacrosAreRoughlyConsistentWithCalories() {
        // Atwater factors should land within a wide tolerance. This catches a
        // transposed column far more reliably than reading the table does.
        //
        // Alcohol is exempt, and legitimately so: ethanol carries about 7 cal/g and is
        // not protein, carbohydrate or fat, so a glass of wine really does have four
        // times the calories its macros imply.
        let alcoholic: Set<String> = ["Beer", "Wine", "Whiskey", "Cocktail"]
        for record in database.records
        where record.factsPerServing.calories > 40 && !alcoholic.contains(record.name) {
            let facts = record.factsPerServing
            let ratio = facts.macroCalories / facts.calories
            XCTAssertTrue(
                (0.6...1.45).contains(ratio),
                "\(record.name): macros imply \(Int(facts.macroCalories)) cal but row says \(Int(facts.calories))"
            )
        }
    }

    // MARK: Scaling

    func testMatchingUnitScalesExactlyAndIsMeasured() {
        let record = try! XCTUnwrap(database.records.first { $0.name == "Toast" })
        let scaled = record.facts(for: Quantity(amount: 3, unit: .slice))
        XCTAssertEqual(scaled.confidence, .measured)
        XCTAssertEqual(scaled.facts.calories, record.factsPerServing.calories * 3, accuracy: 0.01)
    }

    func testMassConvertsThroughTheServingWeight() {
        // The bug this exists for: "200g chicken breast" logged 46,200 calories,
        // because a mass request was treated as a count of servings.
        let record = try! XCTUnwrap(database.records.first { $0.name == "Chicken Breast" })
        let scaled = record.facts(for: Quantity(amount: 200, unit: .gram))
        XCTAssertEqual(scaled.confidence, .measured)
        let expected = record.factsPerServing.calories * 200 / record.servingGrams
        XCTAssertEqual(scaled.facts.calories, expected, accuracy: 0.01)
        XCTAssertLessThan(scaled.facts.calories, 700, "a plausible amount of chicken")
    }

    func testOuncesConvertToo() {
        let record = try! XCTUnwrap(database.records.first { $0.name == "Salmon" })
        let scaled = record.facts(for: Quantity(amount: 6, unit: .ounce))
        XCTAssertEqual(scaled.confidence, .measured)
        XCTAssertEqual(scaled.facts.calories, record.factsPerServing.calories * 170.097 / record.servingGrams, accuracy: 1)
    }

    func testNoScalingPathCanRunAway() {
        // Whatever the phrasing, a single logged food should never be absurd.
        for record in database.records {
            for unit in Quantity.Unit.allCases {
                let scaled = record.facts(for: Quantity(amount: 12, unit: unit))
                XCTAssertLessThan(
                    scaled.facts.calories, 12_000,
                    "\(record.name) at 12 \(unit.rawValue) produced \(Int(scaled.facts.calories)) cal"
                )
            }
        }
    }

    func testEveryRowHasAPlausibleServingMass() {
        for record in database.records {
            XCTAssertGreaterThan(record.servingGrams, 0, record.name)
            XCTAssertLessThan(record.servingGrams, 1000, record.name)
            // Energy density sanity: nothing is more than ~9 cal/g (pure fat).
            XCTAssertLessThan(
                record.factsPerServing.calories / record.servingGrams, 9.2,
                "\(record.name): \(record.factsPerServing.calories) cal in \(record.servingGrams)g"
            )
        }
    }

    func testMismatchedUnitIsOnlyAnEstimate() {
        let record = try! XCTUnwrap(database.records.first { $0.name == "White Rice" })
        let scaled = record.facts(for: Quantity(amount: 2, unit: .bowl))
        XCTAssertEqual(scaled.confidence, .estimated)
        XCTAssertEqual(scaled.facts.calories, record.factsPerServing.calories * 2, accuracy: 0.01)
    }
}
