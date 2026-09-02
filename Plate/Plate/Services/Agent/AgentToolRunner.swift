import Foundation

/// Executes tool calls against the real stores.
///
/// Results are deliberately terse. Every tool result is replayed on every subsequent
/// request in the conversation, so a chatty result is a tax paid once per turn for
/// the rest of the day.
struct AgentToolRunner: Sendable {
    /// The day the conversation is about — not necessarily today. Paging back and
    /// saying "add a coffee" should add it to *that* day.
    let day: DayID
    let store: LogStore
    let database: NutritionDatabase
    let profileStore: ProfileStore

    struct Outcome: Sendable {
        var result: ToolResult
        /// Entries created by this call, in order. The engine attaches these to the
        /// assistant's message so cards appear inline, and kicks off their imagery.
        var loggedEntryIDs: [UUID] = []
        /// True when the day's contents changed and the UI needs to re-read.
        var mutatedLog: Bool = false
    }

    func run(id: String, name: String, input: JSONValue) async -> Outcome {
        guard let tool = ToolName(rawValue: name) else {
            return Outcome(result: ToolResult(
                toolUseID: id,
                content: "Unknown tool '\(name)'.",
                isError: true
            ))
        }

        switch tool {
        case .searchNutrition: return await searchNutrition(id: id, input: input)
        case .logFood: return await logFood(id: id, input: input)
        case .updateFood: return await updateFood(id: id, input: input)
        case .removeFood: return await removeFood(id: id, input: input)
        case .readDay: return await readDay(id: id, input: input)
        case .searchHistory: return await searchHistory(id: id, input: input)
        case .updateProfile: return await updateProfile(id: id, input: input)
        }
    }

    // MARK: Lookup

    private func searchNutrition(id: String, input: JSONValue) async -> Outcome {
        guard let query = input["query"]?.string, !query.isEmpty else {
            return Outcome(result: ToolResult(toolUseID: id, content: "A query is required.", isError: true))
        }
        let limit = min(max(input["limit"]?.int ?? 5, 1), 10)
        let matches = database.search(query, limit: limit)

        guard !matches.isEmpty else {
            return Outcome(result: ToolResult(
                toolUseID: id,
                content: """
                {"results":[],"note":"Nothing in the local database. \
                Estimate from what you know and log with confidence 'guessed'."}
                """
            ))
        }

        let rows = matches.map { match -> JSONValue in
            let record = match.record
            let facts = record.factsPerServing
            return [
                "food": .string(record.name),
                "serving": .string(record.servingLabel),
                "amount": .number(record.serving.amount),
                "unit": .string(record.serving.unit.rawValue),
                "kcal": .number(facts.calories.rounded()),
                "p": .number(round(facts.protein * 10) / 10),
                "c": .number(round(facts.carbs * 10) / 10),
                "f": .number(round(facts.fat * 10) / 10),
                "match": .number(round(match.score * 100) / 100)
            ]
        }

        return Outcome(result: ToolResult(
            toolUseID: id,
            content: JSONValue.object(["results": .array(rows)]).jsonText
        ))
    }

    // MARK: Writing

    private func logFood(id: String, input: JSONValue) async -> Outcome {
        guard let items = input["items"]?.array, !items.isEmpty else {
            return Outcome(result: ToolResult(
                toolUseID: id,
                content: "items must be a non-empty array.",
                isError: true
            ))
        }

        var created: [FoodEntry] = []
        // A day the user paged back to should receive entries stamped at a plausible
        // hour on *that* day, not at the current clock time on it.
        let stamp = timestamp(on: day)

        for item in items {
            guard let name = item["name"]?.string, !name.isEmpty else { continue }

            let quantity = Quantity(
                amount: item["amount"]?.double ?? 1,
                unit: item["unit"]?.string.flatMap(Quantity.Unit.init(rawValue:)) ?? .serving
            )

            let facts = NutritionFacts(
                calories: max(item["calories"]?.double ?? 0, 0),
                protein: max(item["protein"]?.double ?? 0, 0),
                carbs: max(item["carbs"]?.double ?? 0, 0),
                fat: max(item["fat"]?.double ?? 0, 0),
                fiber: item["fiber"]?.double
            )

            let meal = item["meal"]?.string.flatMap(MealSlot.init(rawValue:))
                ?? MealSlot.inferred(from: stamp)

            created.append(
                FoodEntry(
                    name: name,
                    detail: item["detail"]?.string,
                    quantity: quantity,
                    facts: facts,
                    meal: meal,
                    loggedAt: stamp,
                    confidence: item["confidence"]?.string.flatMap(Confidence.init(rawValue:)) ?? .estimated
                )
            )
        }

        guard !created.isEmpty else {
            return Outcome(result: ToolResult(
                toolUseID: id,
                content: "No item had a usable name.",
                isError: true
            ))
        }

        let updated = await store.update(day) { log in
            log.entries.append(contentsOf: created)
        }

        let rows = created.map { entry -> JSONValue in
            ["id": .string(entry.id.uuidString), "food": .string(entry.name), "kcal": .number(entry.facts.calories.rounded())]
        }

        return Outcome(
            result: ToolResult(
                toolUseID: id,
                content: JSONValue.object([
                    "logged": .array(rows),
                    "day_total_kcal": .number(updated.totals.calories.rounded())
                ]).jsonText
            ),
            loggedEntryIDs: created.map(\.id),
            mutatedLog: true
        )
    }

    private func updateFood(id: String, input: JSONValue) async -> Outcome {
        guard let raw = input["entry_id"]?.string, let entryID = UUID(uuidString: raw) else {
            return Outcome(result: ToolResult(toolUseID: id, content: "A valid entry_id is required.", isError: true))
        }
        // The entry may live on a different day than the one being discussed.
        guard let owningDay = await store.locateEntry(entryID) else {
            return Outcome(result: ToolResult(toolUseID: id, content: "No entry with that id.", isError: true))
        }

        let updated = await store.updateEntry(entryID, on: owningDay) { entry in
            if let name = input["name"]?.string, !name.isEmpty {
                entry.name = name
                // The name drives the imagery, so a rename invalidates the picture.
                entry.imageSeed = FoodEntry.seed(for: name)
                entry.image = .none
            }
            if let detail = input["detail"]?.string { entry.detail = detail.isEmpty ? nil : detail }
            if let amount = input["amount"]?.double { entry.quantity.amount = amount }
            if let unit = input["unit"]?.string.flatMap(Quantity.Unit.init(rawValue:)) { entry.quantity.unit = unit }
            if let calories = input["calories"]?.double { entry.facts.calories = max(calories, 0) }
            if let protein = input["protein"]?.double { entry.facts.protein = max(protein, 0) }
            if let carbs = input["carbs"]?.double { entry.facts.carbs = max(carbs, 0) }
            if let fat = input["fat"]?.double { entry.facts.fat = max(fat, 0) }
            if let meal = input["meal"]?.string.flatMap(MealSlot.init(rawValue:)) { entry.meal = meal }
        }

        guard let updated else {
            return Outcome(result: ToolResult(toolUseID: id, content: "No entry with that id.", isError: true))
        }

        return Outcome(
            result: ToolResult(
                toolUseID: id,
                content: JSONValue.object([
                    "updated": .string(updated.name),
                    "kcal": .number(updated.facts.calories.rounded())
                ]).jsonText
            ),
            mutatedLog: true
        )
    }

    private func removeFood(id: String, input: JSONValue) async -> Outcome {
        guard let raw = input["entry_id"]?.string, let entryID = UUID(uuidString: raw),
              let owningDay = await store.locateEntry(entryID) else {
            return Outcome(result: ToolResult(toolUseID: id, content: "No entry with that id.", isError: true))
        }

        var removedName = ""
        await store.update(owningDay) { log in
            if let index = log.entries.firstIndex(where: { $0.id == entryID }) {
                removedName = log.entries[index].name
                log.entries.remove(at: index)
            }
            // A removed entry must not leave a dangling card attached to a message.
            for messageIndex in log.messages.indices {
                log.messages[messageIndex].entryIDs.removeAll { $0 == entryID }
            }
        }

        return Outcome(
            result: ToolResult(toolUseID: id, content: "{\"removed\":\"\(removedName)\"}"),
            mutatedLog: true
        )
    }

    // MARK: Reading

    private func readDay(id: String, input: JSONValue) async -> Outcome {
        let offset = max(input["days_ago"]?.int ?? 0, 0)
        let target = day.advanced(by: -offset)
        let log = await store.day(target)
        let profile = await profileStore.profile()

        let rows = log.entriesInOrder.map { entry -> JSONValue in
            [
                "id": .string(entry.id.uuidString),
                "food": .string(entry.name),
                "qty": .string(entry.quantity.display),
                "meal": .string(entry.meal.rawValue),
                "kcal": .number(entry.facts.calories.rounded()),
                "p": .number(round(entry.facts.protein)),
                "c": .number(round(entry.facts.carbs)),
                "f": .number(round(entry.facts.fat))
            ]
        }

        var payload: [String: JSONValue] = [
            "date": .string(target.description),
            "label": .string(target.title),
            "entries": .array(rows),
            "total_kcal": .number(log.totals.calories.rounded()),
            "total_p": .number(round(log.totals.protein)),
            "total_c": .number(round(log.totals.carbs)),
            "total_f": .number(round(log.totals.fat))
        ]
        if let target = profile.calorieTarget {
            payload["kcal_target"] = .number(target)
            payload["kcal_remaining"] = .number((target - log.totals.calories).rounded())
        }
        if let target = profile.proteinTarget {
            payload["protein_target"] = .number(target)
        }

        return Outcome(result: ToolResult(toolUseID: id, content: JSONValue.object(payload).jsonText))
    }

    private func searchHistory(id: String, input: JSONValue) async -> Outcome {
        let query = input["query"]?.string ?? ""
        let days = min(max(input["days"]?.int ?? 30, 1), 365)
        let hits = await store.searchHistory(query: query, limit: 8, searchingBack: days)

        let rows = hits.map { hit -> JSONValue in
            [
                "food": .string(hit.entry.name),
                "qty": .string(hit.entry.quantity.display),
                "kcal": .number(hit.entry.facts.calories.rounded()),
                "p": .number(round(hit.entry.facts.protein)),
                "c": .number(round(hit.entry.facts.carbs)),
                "f": .number(round(hit.entry.facts.fat)),
                "when": .string(hit.day.description)
            ]
        }

        return Outcome(result: ToolResult(
            toolUseID: id,
            content: JSONValue.object(["matches": .array(rows)]).jsonText
        ))
    }

    private func updateProfile(id: String, input: JSONValue) async -> Outcome {
        let updated = await profileStore.update { profile in
            if let value = input["calorie_target"]?.double, value > 0 { profile.calorieTarget = value }
            if let value = input["protein_target"]?.double, value > 0 { profile.proteinTarget = value }
            if let value = input["context"]?.string { profile.context = value.isEmpty ? nil : value }
            if let value = input["name"]?.string, !value.isEmpty { profile.name = value }
        }

        var payload: [String: JSONValue] = ["saved": .bool(true)]
        if let target = updated.calorieTarget { payload["kcal_target"] = .number(target) }
        if let target = updated.proteinTarget { payload["protein_target"] = .number(target) }

        return Outcome(result: ToolResult(toolUseID: id, content: JSONValue.object(payload).jsonText))
    }

    // MARK: Helpers

    /// A sensible instant on `day`. Today gets the real clock; a past day gets a time
    /// that reflects when that kind of meal usually happens, so ordering stays sane.
    private func timestamp(on day: DayID) -> Date {
        if day.isToday { return .now }
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        let hour = Calendar.current.component(.hour, from: .now)
        components.hour = day.isFuture ? 9 : hour
        components.minute = Calendar.current.component(.minute, from: .now)
        return Calendar.current.date(from: components) ?? day.date()
    }
}
