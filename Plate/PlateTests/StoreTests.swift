import XCTest
@testable import Plate

final class LogStoreTests: XCTestCase {
    private var root: URL!
    private var store: LogStore!

    override func setUp() async throws {
        root = URL.temporaryDirectory.appending(path: "PlateTests-\(UUID().uuidString)")
        store = LogStore(root: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(_ name: String, calories: Double = 100, meal: MealSlot = .lunch) -> FoodEntry {
        FoodEntry(
            name: name,
            facts: NutritionFacts(calories: calories, protein: 10, carbs: 10, fat: 3),
            meal: meal
        )
    }

    func testUnknownDayIsEmptyRatherThanMissing() async {
        let day = await store.day(DayID(year: 2020, month: 1, day: 1))
        XCTAssertTrue(day.isEmpty)
    }

    func testWriteThenReadBackFromDisk() async throws {
        let id = DayID(year: 2026, month: 5, day: 4)
        await store.update(id) { $0.entries.append(self.entry("Toast")) }
        await store.flush()

        // A fresh store shares nothing but the directory.
        let reopened = LogStore(root: root)
        let log = await reopened.day(id)
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries.first?.name, "Toast")
    }

    func testKnownDaysListsWhatIsOnDisk() async throws {
        // This is the path that `URL.path()` broke: the container path contains a
        // space, so a string-based directory listing silently returned nothing.
        for offset in 0..<3 {
            await store.update(DayID.today.advanced(by: -offset)) {
                $0.entries.append(self.entry("Food \(offset)"))
            }
        }
        await store.flush()

        let reopened = LogStore(root: root)
        let days = await reopened.knownDays()
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days, days.sorted(by: >), "knownDays must be newest first")
    }

    func testDirectoryWithASpaceInItStillLists() async throws {
        let spaced = URL.temporaryDirectory.appending(path: "Plate Tests \(UUID().uuidString)")
        let spacedStore = LogStore(root: spaced)
        defer { try? FileManager.default.removeItem(at: spaced) }

        await spacedStore.update(.today) { $0.entries.append(self.entry("Egg")) }
        await spacedStore.flush()

        let reopened = LogStore(root: spaced)
        let listed = await reopened.knownDays()
        XCTAssertEqual(listed.count, 1)
    }

    func testTotalsSumEveryEntry() async {
        await store.update(.today) {
            $0.entries.append(self.entry("A", calories: 100))
            $0.entries.append(self.entry("B", calories: 250))
        }
        let totals = await store.day(.today).totals
        XCTAssertEqual(totals.calories, 350)
        XCTAssertEqual(totals.protein, 20)
    }

    func testEntriesGroupIntoMealsAndSkipEmptySlots() async {
        await store.update(.today) {
            $0.entries.append(self.entry("Dinner thing", meal: .dinner))
            $0.entries.append(self.entry("Breakfast thing", meal: .breakfast))
        }
        let grouped = await store.day(.today).byMeal
        XCTAssertEqual(grouped.map(\.slot), [.breakfast, .dinner])
    }

    func testLocateEntryFindsItOnAPastDay() async {
        let target = DayID.today.advanced(by: -4)
        let food = entry("Ramen")
        await store.update(target) { $0.entries.append(food) }
        let located = await store.locateEntry(food.id)
        XCTAssertEqual(located, target)
    }

    func testUpdateEntryMutatesInPlace() async {
        let food = entry("Ramen")
        await store.update(.today) { $0.entries.append(food) }
        await store.updateEntry(food.id, on: .today) { $0.facts.calories = 999 }
        let updated = await store.day(.today).entry(food.id)
        XCTAssertEqual(updated?.facts.calories, 999)
    }

    func testHistorySearchIsRecentFirstAndDeduplicatedByName() async {
        for offset in 0..<4 {
            await store.update(DayID.today.advanced(by: -offset)) {
                $0.entries.append(self.entry("Oatmeal", calories: Double(100 + offset)))
            }
        }
        let hits = await store.searchHistory(query: "oatmeal")
        XCTAssertEqual(hits.count, 1, "the same food on four days should collapse to one suggestion")
        XCTAssertEqual(hits.first?.day, .today)
    }

    func testHistorySearchMatchesPartially() async {
        await store.update(.today) { $0.entries.append(self.entry("Chicken Shawarma Bowl")) }
        let shawarma = await store.searchHistory(query: "shawarma")
        let sushi = await store.searchHistory(query: "sushi")
        XCTAssertEqual(shawarma.count, 1)
        XCTAssertEqual(sushi.count, 0)
    }

    func testCorruptDayIsQuarantinedNotFatal() async throws {
        let id = DayID(year: 2026, month: 7, day: 7)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: root.appending(path: "\(id.description).json"))

        let log = await store.day(id)
        XCTAssertTrue(log.isEmpty, "a corrupt day should read as empty, not crash")

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        XCTAssertTrue(names.contains { $0.contains("corrupt") }, "the bad file should be kept for recovery")
    }
}

final class AgentToolRunnerTests: XCTestCase {
    private var root: URL!
    private var store: LogStore!
    private var profileStore: ProfileStore!
    private var runner: AgentToolRunner!

    override func setUp() async throws {
        root = URL.temporaryDirectory.appending(path: "PlateTests-\(UUID().uuidString)")
        store = LogStore(root: root.appending(path: "days"))
        profileStore = ProfileStore(url: root.appending(path: "profile.json"))
        runner = AgentToolRunner(
            day: .today,
            store: store,
            database: .shared,
            profileStore: profileStore
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func run(_ tool: ToolName, _ input: JSONValue) async -> AgentToolRunner.Outcome {
        await runner.run(id: UUID().uuidString, name: tool.rawValue, input: input)
    }

    private func decode(_ outcome: AgentToolRunner.Outcome) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(outcome.result.content.utf8))
    }

    func testLogFoodWritesEveryItemInOneCall() async throws {
        let outcome = await run(.logFood, [
            "items": .array([
                ["name": "Egg", "calories": 144, "protein": 12.6, "carbs": 0.8, "fat": 9.6, "amount": 2, "unit": "piece"],
                ["name": "Toast", "calories": 79, "protein": 2.7, "carbs": 14.3, "fat": 1, "unit": "slice"]
            ])
        ])

        XCTAssertEqual(outcome.loggedEntryIDs.count, 2)
        XCTAssertTrue(outcome.mutatedLog)
        XCTAssertEqual(try decode(outcome)["day_total_kcal"]?.double, 223)
        let stored = await store.day(.today).entries
        XCTAssertEqual(stored.count, 2)
    }

    func testLogFoodRejectsAnEmptyBatch() async {
        let outcome = await run(.logFood, ["items": .array([])])
        XCTAssertTrue(outcome.result.isError)
        XCTAssertFalse(outcome.mutatedLog)
    }

    func testNegativeNumbersAreClampedRatherThanTrusted() async throws {
        let outcome = await run(.logFood, [
            "items": .array([["name": "Odd", "calories": -50, "protein": -1, "carbs": 0, "fat": 0]])
        ])
        let id = try XCTUnwrap(outcome.loggedEntryIDs.first)
        let day = await store.day(.today)
        let entry = try XCTUnwrap(day.entry(id))
        XCTAssertEqual(entry.facts.calories, 0)
        XCTAssertEqual(entry.facts.protein, 0)
    }

    func testUpdateFoodChangesOnlyWhatWasSent() async throws {
        let logged = await run(.logFood, [
            "items": .array([["name": "Latte", "calories": 190, "protein": 10, "carbs": 19, "fat": 7]])
        ])
        let id = try XCTUnwrap(logged.loggedEntryIDs.first)

        _ = await run(.updateFood, ["entry_id": .string(id.uuidString), "calories": 240])

        let day = await store.day(.today)
        let entry = try XCTUnwrap(day.entry(id))
        XCTAssertEqual(entry.facts.calories, 240)
        XCTAssertEqual(entry.facts.protein, 10, "untouched fields must survive")
        XCTAssertEqual(entry.name, "Latte")
    }

    func testRenamingInvalidatesTheImage() async throws {
        let logged = await run(.logFood, [
            "items": .array([["name": "Latte", "calories": 190, "protein": 10, "carbs": 19, "fat": 7]])
        ])
        let id = try XCTUnwrap(logged.loggedEntryIDs.first)
        await store.updateEntry(id, on: .today) { $0.image = .ready(fileName: "old.jpg") }

        _ = await run(.updateFood, ["entry_id": .string(id.uuidString), "name": "Flat White"])

        let day = await store.day(.today)
        let entry = try XCTUnwrap(day.entry(id))
        XCTAssertEqual(entry.image, .none, "a renamed food should not keep the old photograph")
        XCTAssertEqual(entry.imageSeed, FoodEntry.seed(for: "Flat White"))
    }

    func testRemoveFoodAlsoDetachesItFromItsMessage() async throws {
        let logged = await run(.logFood, [
            "items": .array([["name": "Toast", "calories": 79, "protein": 3, "carbs": 14, "fat": 1]])
        ])
        let id = try XCTUnwrap(logged.loggedEntryIDs.first)
        await store.update(.today) {
            $0.messages.append(ChatMessage(role: .agent, text: "Added.", entryIDs: [id]))
        }

        _ = await run(.removeFood, ["entry_id": .string(id.uuidString)])

        let log = await store.day(.today)
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertTrue(log.messages.allSatisfy { $0.entryIDs.isEmpty }, "no dangling card references")
    }

    func testUnknownEntryIsAnErrorNotACrash() async {
        let outcome = await run(.updateFood, ["entry_id": .string(UUID().uuidString), "calories": 1])
        XCTAssertTrue(outcome.result.isError)
    }

    func testMalformedEntryIDIsAnError() async {
        let outcome = await run(.removeFood, ["entry_id": "not-a-uuid"])
        XCTAssertTrue(outcome.result.isError)
    }

    func testReadDayReportsTotalsAndRemaining() async throws {
        _ = await run(.updateProfile, ["calorie_target": 2000])
        _ = await run(.logFood, [
            "items": .array([["name": "Pizza", "calories": 570, "protein": 24, "carbs": 68, "fat": 22]])
        ])

        let payload = try decode(await run(.readDay, .object([:])))
        XCTAssertEqual(payload["total_kcal"]?.double, 570)
        XCTAssertEqual(payload["kcal_target"]?.double, 2000)
        XCTAssertEqual(payload["kcal_remaining"]?.double, 1430)
        XCTAssertEqual(payload["entries"]?.array?.count, 1)
    }

    func testSearchNutritionReturnsCandidates() async throws {
        let payload = try decode(await run(.searchNutrition, ["query": "greek yogurt", "limit": 3]))
        let results = try XCTUnwrap(payload["results"]?.array)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?["food"]?.string, "Greek Yogurt")
        XCTAssertNotNil(results.first?["kcal"]?.double)
    }

    func testSearchNutritionMissTellsTheModelWhatToDo() async {
        let outcome = await run(.searchNutrition, ["query": "zzzqqxwv"])
        XCTAssertFalse(outcome.result.isError)
        XCTAssertTrue(outcome.result.content.contains("guessed"))
    }

    func testProfileUpdatesPersist() async {
        _ = await run(.updateProfile, ["calorie_target": 2200, "name": "Sam", "context": "vegetarian"])
        let profile = await profileStore.profile()
        XCTAssertEqual(profile.calorieTarget, 2200)
        XCTAssertEqual(profile.name, "Sam")
        XCTAssertEqual(profile.context, "vegetarian")
    }

    func testEntriesLandOnTheDayBeingDiscussed() async throws {
        let pastDay = DayID.today.advanced(by: -5)
        let pastRunner = AgentToolRunner(
            day: pastDay,
            store: store,
            database: .shared,
            profileStore: profileStore
        )
        let outcome = await pastRunner.run(
            id: "1",
            name: ToolName.logFood.rawValue,
            input: ["items": .array([["name": "Soup", "calories": 145, "protein": 6, "carbs": 20, "fat": 4]])]
        )

        let pastLog = await store.day(pastDay)
        let todayLog = await store.day(.today)
        XCTAssertEqual(outcome.loggedEntryIDs.count, 1)
        XCTAssertEqual(pastLog.entries.count, 1)
        XCTAssertTrue(todayLog.entries.isEmpty)

        // And the timestamp must fall on that day, or it sorts into the wrong section.
        let entry = try XCTUnwrap(pastLog.entries.first)
        XCTAssertEqual(DayID(entry.loggedAt), pastDay)
    }
}
