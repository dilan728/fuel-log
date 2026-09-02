import Foundation

/// The tools the agent can call.
///
/// Two rules shape this surface. First, tools are *coarse*: `log_food` takes an array
/// of items, because "eggs, toast and a coffee" is one thought and should be one call.
/// Second, every tool returns compact JSON with short keys — tool results are re-sent
/// on every subsequent turn, so verbose results are paid for repeatedly.
enum ToolName: String, CaseIterable, Sendable {
    case searchNutrition = "search_nutrition"
    case logFood = "log_food"
    case updateFood = "update_food"
    case removeFood = "remove_food"
    case readDay = "read_day"
    case searchHistory = "search_history"
    case updateProfile = "update_profile"
}

enum AgentTools {

    // MARK: Definitions

    static var definitions: [JSONValue] {
        [
            tool(
                .searchNutrition,
                "Look up nutrition for a food. Always call this before logging anything you are not certain about — it is cheap and its numbers are better than your recall. Returns candidate foods with per-serving nutrition.",
                properties: [
                    "query": string("The food to look up, e.g. 'chicken shawarma' or 'oat milk latte'."),
                    "limit": integer("How many candidates to return. Default 5.")
                ],
                required: ["query"]
            ),
            tool(
                .logFood,
                "Add one or more foods to the day being discussed. Log everything the user mentioned in a single call rather than one call per food.",
                properties: [
                    "items": .object([
                        "type": "array",
                        "description": "The foods to log.",
                        "items": .object([
                            "type": "object",
                            "properties": .object([
                                "name": string("Short title-cased food name, no quantity in it. 'Chicken Shawarma Bowl'."),
                                "detail": string("Optional qualifier: 'extra garlic sauce, no rice'."),
                                "amount": number("How many units. Default 1."),
                                "unit": .object([
                                    "type": "string",
                                    "description": "Unit for amount.",
                                    "enum": .array(Quantity.Unit.allCases.map { .string($0.rawValue) })
                                ]),
                                "calories": number("Total calories for this amount, not per serving."),
                                "protein": number("Grams of protein for this amount."),
                                "carbs": number("Grams of carbohydrate for this amount."),
                                "fat": number("Grams of fat for this amount."),
                                "fiber": number("Grams of fibre, if known."),
                                "meal": .object([
                                    "type": "string",
                                    "description": "Which meal this belongs to. Omit to infer from the time of day.",
                                    "enum": .array(MealSlot.allCases.map { .string($0.rawValue) })
                                ]),
                                "confidence": .object([
                                    "type": "string",
                                    "description": "'measured' if from a database row with a stated portion, 'estimated' if the portion was inferred, 'guessed' if you had no lookup to work from.",
                                    "enum": ["measured", "estimated", "guessed"]
                                ])
                            ]),
                            "required": ["name", "calories", "protein", "carbs", "fat"]
                        ])
                    ])
                ],
                required: ["items"]
            ),
            tool(
                .updateFood,
                "Change something already logged. Only send the fields that change.",
                properties: [
                    "entry_id": string("The id of the entry, from read_day or a previous log_food."),
                    "name": string("New name."),
                    "detail": string("New qualifier."),
                    "amount": number("New amount."),
                    "unit": string("New unit."),
                    "calories": number("New total calories."),
                    "protein": number("New grams of protein."),
                    "carbs": number("New grams of carbohydrate."),
                    "fat": number("New grams of fat."),
                    "meal": string("New meal slot.")
                ],
                required: ["entry_id"]
            ),
            tool(
                .removeFood,
                "Delete something from the day.",
                properties: ["entry_id": string("The id of the entry to remove.")],
                required: ["entry_id"]
            ),
            tool(
                .readDay,
                "Read what is logged on a day, with totals. Call this before answering any question about how the user is doing.",
                properties: [
                    "days_ago": integer("0 for the day being discussed, 1 for the day before it, and so on. Default 0.")
                ],
                required: []
            ),
            tool(
                .searchHistory,
                "Search what the user has eaten before. Use it when they say 'the usual', 'same as yesterday', or ask about patterns.",
                properties: [
                    "query": string("Food name to search for. Omit to get their most recent foods."),
                    "days": integer("How many days back to look. Default 30.")
                ],
                required: []
            ),
            tool(
                .updateProfile,
                "Record a lasting fact about the user: a calorie or protein target, or context like a diet or allergy. Only call this when they tell you something that should persist beyond today.",
                properties: [
                    "calorie_target": number("Daily calorie goal."),
                    "protein_target": number("Daily protein goal in grams."),
                    "context": string("Free text about diet, goals, allergies. Replaces any previous context, so include what still applies."),
                    "name": string("What to call them.")
                ],
                required: []
            )
        ]
    }

    // MARK: Activity labels
    //
    // The single place tool plumbing is translated into something a person reads.
    // If a tool name ever reaches the screen, it came from a path that skipped this.

    static func activityLabel(for name: String, input: JSONValue) -> Activity {
        switch ToolName(rawValue: name) {
        case .searchNutrition:
            let query = input["query"]?.string ?? "that"
            return Activity(
                label: "Looking up \(query)",
                completedLabel: "Looked up \(query)",
                kind: .lookup
            )
        case .logFood:
            let count = input["items"]?.array?.count ?? 1
            let names = input["items"]?.array?.compactMap { $0["name"]?.string } ?? []
            let label = names.count == 1 ? names[0] : "\(count) items"
            return Activity(label: "Adding \(label)", completedLabel: "Added \(label)", kind: .writing)
        case .updateFood:
            return Activity(label: "Updating that entry", completedLabel: "Updated", kind: .writing)
        case .removeFood:
            return Activity(label: "Removing that entry", completedLabel: "Removed", kind: .writing)
        case .readDay:
            return Activity(label: "Checking the day", completedLabel: "Checked the day", kind: .history)
        case .searchHistory:
            let query = input["query"]?.string
            return Activity(
                label: query.map { "Looking back for \($0)" } ?? "Looking back through your history",
                completedLabel: "Checked your history",
                kind: .history
            )
        case .updateProfile:
            return Activity(label: "Noting that down", completedLabel: "Noted", kind: .writing)
        case nil:
            return Activity(label: "Working", completedLabel: nil, kind: .thinking)
        }
    }

    // MARK: Schema helpers

    private static func tool(
        _ name: ToolName,
        _ description: String,
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        [
            "name": .string(name.rawValue),
            "description": .string(description),
            "input_schema": .object([
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map { .string($0) })
            ])
        ]
    }

    private static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    private static func number(_ description: String) -> JSONValue {
        ["type": "number", "description": .string(description)]
    }

    private static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }
}
