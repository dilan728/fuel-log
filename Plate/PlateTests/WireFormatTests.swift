import XCTest
@testable import Plate

final class JSONValueTests: XCTestCase {

    private func decode(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testRoundTripsEveryShape() throws {
        let text = #"{"a":1,"b":"two","c":[true,null,3.5],"d":{"e":{}}}"#
        let value = try decode(text)
        let reencoded = try JSONEncoder().encode(value)
        let again = try JSONDecoder().decode(JSONValue.self, from: reencoded)
        XCTAssertEqual(value, again)
    }

    func testLenientReadsBecauseModelsAreNotAlwaysExact() throws {
        // The schema says number; models sometimes send a string. A tool call should
        // not fail over that.
        let value = try decode(#"{"amount":"2.5","count":3,"flag":"yes"}"#)
        XCTAssertEqual(value["amount"]?.double, 2.5)
        XCTAssertEqual(value["count"]?.int, 3)
        XCTAssertEqual(value["flag"]?.bool, true)
        XCTAssertEqual(value["count"]?.string, "3")
    }

    func testMissingAndWrongTypedFieldsAreNilNotThrowing() throws {
        let value = try decode(#"{"a":1}"#)
        XCTAssertNil(value["missing"]?.string)
        XCTAssertNil(value["a"]?.array)
        XCTAssertNil(JSONValue.string("x")["a"])
    }

    func testJSONTextIsCompactAndDeterministic() {
        let value = JSONValue.object(["b": 2, "a": 1])
        XCTAssertEqual(value.jsonText, #"{"a":1,"b":2}"#)
    }
}

final class ContentBlockTests: XCTestCase {

    func testTextRoundTrip() {
        let block = ContentBlock.text("hello")
        XCTAssertEqual(ContentBlock.from(wire: block.wireJSON), block)
    }

    func testToolUseRoundTrip() {
        let block = ContentBlock.toolUse(id: "toolu_1", name: "log_food", input: ["items": .array([])])
        guard case .toolUse(let id, let name, let input) = ContentBlock.from(wire: block.wireJSON) else {
            return XCTFail("Expected .toolUse")
        }
        XCTAssertEqual(id, "toolu_1")
        XCTAssertEqual(name, "log_food")
        XCTAssertNotNil(input["items"]?.array)
    }

    func testUnknownBlocksArePreservedByteForByte() {
        // Thinking blocks (and whatever ships next) must replay unmodified or the API
        // rejects the request. Modelling them field-by-field would break on any change.
        let wire: JSONValue = [
            "type": "thinking",
            "thinking": "…",
            "signature": "abc123",
            "some_future_field": .array([1, 2, 3])
        ]
        let block = ContentBlock.from(wire: wire)
        guard case .opaque = block else { return XCTFail("Expected .opaque") }
        XCTAssertEqual(block.wireJSON, wire)
        XCTAssertEqual(block.wireJSON.jsonText, wire.jsonText)
    }

    func testToolResultsAreOneUserTurn() {
        // Splitting tool results across messages teaches the model to stop batching
        // its calls, so this shape matters.
        let turn = AgentTurn.toolResults([
            ToolResult(toolUseID: "a", content: "{}"),
            ToolResult(toolUseID: "b", content: "{}", isError: true)
        ])
        XCTAssertEqual(turn.role, .user)
        XCTAssertEqual(turn.blocks.count, 2)
        XCTAssertEqual(turn.blocks[1].wireJSON["is_error"]?.bool, true)
    }

    func testTurnExposesItsToolCalls() {
        let turn = AgentTurn(role: .assistant, blocks: [
            .text("one moment"),
            .toolUse(id: "t1", name: "read_day", input: .object([:]))
        ])
        XCTAssertEqual(turn.plainText, "one moment")
        XCTAssertEqual(turn.toolUses.count, 1)
        XCTAssertEqual(turn.toolUses.first?.name, "read_day")
    }
}

final class ActivityLabelTests: XCTestCase {

    func testLabelsNeverLeakToolPlumbing() {
        // The one guarantee: nothing technical reaches the screen.
        let forbidden = ["tool", "json", "schema", "api", "function", "claude", "model", "_"]
        for name in ToolName.allCases {
            let activity = AgentTools.activityLabel(for: name.rawValue, input: .object([:]))
            let text = (activity.label + " " + (activity.completedLabel ?? "")).lowercased()
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(name.rawValue) label leaked '\(word)': \(text)")
            }
            XCTAssertFalse(activity.label.isEmpty)
        }
    }

    func testLabelsUseTheArgumentsWhenTheyHaveThem() {
        let activity = AgentTools.activityLabel(
            for: ToolName.searchNutrition.rawValue,
            input: ["query": "chicken shawarma"]
        )
        XCTAssertEqual(activity.label, "Looking up chicken shawarma")
        XCTAssertEqual(activity.completedLabel, "Looked up chicken shawarma")
    }

    func testUnknownToolStillProducesSomethingSayable() {
        let activity = AgentTools.activityLabel(for: "not_a_tool", input: .object([:]))
        XCTAssertEqual(activity.kind, .thinking)
        XCTAssertFalse(activity.label.isEmpty)
    }

    func testEveryToolHasASchema() {
        let names = Set(AgentTools.definitions.compactMap { $0["name"]?.string })
        XCTAssertEqual(names, Set(ToolName.allCases.map(\.rawValue)))
        for definition in AgentTools.definitions {
            XCTAssertNotNil(definition["input_schema"]?["properties"]?.object)
            XCTAssertFalse((definition["description"]?.string ?? "").isEmpty)
        }
    }
}

final class SystemPromptTests: XCTestCase {

    func testFrozenPrefixHasNoVolatileContent() {
        // The frozen half carries the cache breakpoint. A date in it would invalidate
        // the cache on every request, silently, forever.
        let frozen = SystemPrompt.frozen.lowercased()
        XCTAssertFalse(frozen.contains("today is"))
        XCTAssertFalse(frozen.contains("\(DayID.today.year)"))
        XCTAssertFalse(frozen.contains("yesterday is"))
    }

    func testContextNamesTheDayBeingDiscussed() {
        let profile = UserProfile(name: "Sam", calorieTarget: 2200)
        let context = SystemPrompt.context(day: DayID.today.advanced(by: -3), profile: profile)
        XCTAssertTrue(context.contains("3 days ago"))
        XCTAssertTrue(context.contains("Sam"))
        XCTAssertTrue(context.contains("2200"))
    }

    func testBriefingIsNilWhenThereIsNothingToSay() {
        XCTAssertNil(UserProfile().agentBriefing)
    }
}
