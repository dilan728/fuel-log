import XCTest
@testable import Plate

/// The no-key path is only as good as this parser, so it gets the most cases.
final class PhraseParsingTests: XCTestCase {

    func testSplitsOnCommasAndConjunctions() {
        XCTAssertEqual(
            FoodPhrase.split("two eggs and toast, and a black coffee"),
            ["two eggs", "toast", "a black coffee"]
        )
    }

    func testStripsLeadingNarration() {
        XCTAssertEqual(FoodPhrase.split("I had a bagel"), ["a bagel"])
        XCTAssertEqual(FoodPhrase.split("just had ramen"), ["ramen"])
        XCTAssertEqual(FoodPhrase.split("I ate pizza"), ["pizza"])
    }

    func testParsesDigitAmountAndUnit() {
        let parsed = FoodPhrase.parse("3 slices of toast")
        XCTAssertEqual(parsed.amount, 3)
        XCTAssertEqual(parsed.unit, .slice)
        XCTAssertEqual(parsed.food, "toast")
    }

    func testParsesWordAmounts() {
        XCTAssertEqual(FoodPhrase.parse("two eggs").amount, 2)
        XCTAssertEqual(FoodPhrase.parse("a banana").amount, 1)
        XCTAssertEqual(FoodPhrase.parse("half an avocado").amount, 0.5)
        XCTAssertEqual(FoodPhrase.parse("a dozen wings").amount, 12)
    }

    func testUnitIsNilWhenNoUnitWordIsPresent() {
        // This distinction is load-bearing: with no unit word the backend multiplies
        // the database's own serving instead of inventing ".piece".
        let parsed = FoodPhrase.parse("two eggs")
        XCTAssertNil(parsed.unit)
        XCTAssertEqual(parsed.food, "eggs")
    }

    func testBareUnitMeansOne() {
        let parsed = FoodPhrase.parse("bowl of oatmeal")
        XCTAssertNil(parsed.amount)
        XCTAssertEqual(parsed.unit, .bowl)
        XCTAssertEqual(parsed.food, "oatmeal")
    }

    func testFoodWithNoQuantityIsUntouched() {
        let parsed = FoodPhrase.parse("chicken shawarma bowl")
        XCTAssertNil(parsed.amount)
        // "bowl" trails rather than leads, so it is part of the name.
        XCTAssertEqual(parsed.food, "chicken shawarma bowl")
    }

    func testTightUnits() {
        let parsed = FoodPhrase.parse("200g chicken")
        XCTAssertEqual(parsed.amount, 200)
        XCTAssertEqual(parsed.unit, .gram)
        XCTAssertEqual(parsed.food, "chicken")
    }
}

final class IntentTests: XCTestCase {

    func testLoggingIsTheDefault() {
        guard case .log = Intent.classify("two eggs and toast") else {
            return XCTFail("Expected .log")
        }
    }

    func testRemovalAndSubject() {
        guard case .remove(let subject) = Intent.classify("remove the coffee") else {
            return XCTFail("Expected .remove")
        }
        XCTAssertEqual(subject, "coffee")
    }

    func testStatusQuestions() {
        for phrase in ["how am i doing", "how many calories left", "what did i eat today", "what's my total"] {
            guard case .status = Intent.classify(phrase) else {
                return XCTFail("Expected .status for \(phrase)")
            }
        }
    }

    func testTargetSetting() {
        guard case .setTarget(let value) = Intent.classify("my target is 2200 calories") else {
            return XCTFail("Expected .setTarget")
        }
        XCTAssertEqual(value, 2200)
    }

    func testImplausibleTargetsAreNotTargets() {
        // "goal" plus a number that cannot plausibly be a daily calorie target.
        XCTAssertNil(Intent.calorieTargetForTesting("goal 12"))
        XCTAssertNil(Intent.calorieTargetForTesting("goal 999999"))
    }

    func testNumberWithoutAGoalWordIsNotATarget() {
        // "2000" on its own is far more likely to be part of a food description.
        XCTAssertNil(Intent.calorieTargetForTesting("2000 mg sodium"))
    }
}

extension Intent {
    /// Small seam so the private-ish parsing rule can be asserted directly.
    static func calorieTargetForTesting(_ text: String) -> Double? {
        calorieTarget(in: text.lowercased())
    }
}
