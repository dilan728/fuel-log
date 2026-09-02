import Foundation

/// The agent when there is no API key.
///
/// This is not a stub. It parses real phrasing ("2 eggs, toast and a black coffee"),
/// performs real lookups against the bundled database, and writes through the same
/// tool runner the model uses — so the log it produces is indistinguishable from the
/// model's. It handles logging, removal, corrections to quantity, day summaries, and
/// setting a target, which is most of what the app is for.
///
/// It replies a word at a time on purpose. Not to pretend to be a model, but because
/// the streaming presentation *is* the app's reading rhythm, and a reply that appears
/// all at once feels like a different product.
@MainActor
final class LocalAgentBackend: AgentBackend {
    private let database: NutritionDatabase

    init(database: NutritionDatabase = .shared) {
        self.database = database
    }

    func run(userText: String, context: AgentRunContext, sink: AgentSink) async {
        sink.beginReply()

        switch Intent.classify(userText) {
        case .status:
            await answerStatus(context: context, sink: sink)
        case .remove(let subject):
            await remove(subject: subject, context: context, sink: sink)
        case .setTarget(let calories):
            await setTarget(calories, context: context, sink: sink)
        case .log:
            await logFoods(from: userText, context: context, sink: sink)
        }

        // The local backend keeps no wire transcript — there is no model to replay it to.
        sink.recordTurns([])
        sink.finishReply(error: nil)
    }

    // MARK: Logging

    private func logFoods(from text: String, context: AgentRunContext, sink: AgentSink) async {
        let phrases = FoodPhrase.split(text)
        guard !phrases.isEmpty else {
            await stream(Self.confused, into: sink)
            return
        }

        let chip = sink.beginActivity(
            Activity(label: "Looking those up", completedLabel: "Looked them up", kind: .lookup)
        )

        var items: [JSONValue] = []
        var unmatched: [String] = []

        for phrase in phrases {
            let parsed = FoodPhrase.parse(phrase)
            guard let match = database.bestMatch(parsed.food) else {
                unmatched.append(parsed.food)
                continue
            }

            // With an explicit unit, honour it. With a bare count, multiply the
            // database's own serving — "two eggs" is two servings of egg, not two of
            // some unit we invented.
            let serving = match.record.serving
            let quantity: Quantity
            if let unit = parsed.unit {
                quantity = Quantity(amount: parsed.amount ?? 1, unit: unit)
            } else if let amount = parsed.amount, serving.unit.isCountLike {
                // A bare count only multiplies a serving when the serving is itself a
                // count. "a dozen almonds" against a per-handful row is not twelve
                // handfuls, and we have no idea what one almond weighs — so fall
                // through to a single serving rather than inventing a number.
                quantity = Quantity(amount: amount * serving.amount, unit: serving.unit)
            } else {
                quantity = serving
            }
            let scaled = match.record.facts(for: quantity)

            items.append([
                "name": .string(match.record.name),
                "amount": .number(quantity.amount),
                "unit": .string(quantity.unit.rawValue),
                "calories": .number(scaled.facts.calories),
                "protein": .number(scaled.facts.protein),
                "carbs": .number(scaled.facts.carbs),
                "fat": .number(scaled.facts.fat),
                "fiber": scaled.facts.fiber.map { JSONValue.number($0) } ?? .null,
                "confidence": .string(scaled.confidence.rawValue)
            ])
        }

        sink.completeActivity(chip)

        guard !items.isEmpty else {
            await stream(
                "I don't have \(FoodPhrase.list(unmatched)) in my offline list. "
                + "Add an Anthropic key in Settings and I can work it out properly.",
                into: sink
            )
            return
        }

        let writeChip = sink.beginActivity(
            Activity(label: "Adding to your day", completedLabel: "Added", kind: .writing)
        )
        let outcome = await context.runner.run(
            id: UUID().uuidString,
            name: ToolName.logFood.rawValue,
            input: ["items": .array(items)]
        )
        sink.completeActivity(writeChip)

        if !outcome.loggedEntryIDs.isEmpty { sink.attachEntries(outcome.loggedEntryIDs) }
        if outcome.mutatedLog { sink.logDidChange() }

        let total = await context.runner.store.day(context.day).totals.calories
        var reply = Self.acknowledgement(count: items.count)
        if !unmatched.isEmpty {
            reply += " I didn't have \(FoodPhrase.list(unmatched)), so that's not counted."
        }
        reply += " You're at \(Self.formatted(total)) for the day."
        await stream(reply, into: sink)
    }

    // MARK: Removal

    private func remove(subject: String, context: AgentRunContext, sink: AgentSink) async {
        let log = await context.runner.store.day(context.day)
        let needle = NutritionDatabase.normalize(subject)

        let target = log.entriesInOrder.reversed().first { entry in
            needle.isEmpty || NutritionDatabase.normalize(entry.name).contains(needle)
                || needle.contains(NutritionDatabase.normalize(entry.name))
        }

        guard let target else {
            await stream("I can't find \(subject.isEmpty ? "that" : subject) on this day.", into: sink)
            return
        }

        let chip = sink.beginActivity(
            Activity(label: "Removing \(target.name)", completedLabel: "Removed \(target.name)", kind: .writing)
        )
        let outcome = await context.runner.run(
            id: UUID().uuidString,
            name: ToolName.removeFood.rawValue,
            input: ["entry_id": .string(target.id.uuidString)]
        )
        sink.completeActivity(chip)
        if outcome.mutatedLog { sink.logDidChange() }

        let total = await context.runner.store.day(context.day).totals.calories
        await stream("Gone. That brings you to \(Self.formatted(total)).", into: sink)
    }

    // MARK: Status

    private func answerStatus(context: AgentRunContext, sink: AgentSink) async {
        let chip = sink.beginActivity(
            Activity(label: "Checking the day", completedLabel: "Checked the day", kind: .history)
        )
        let log = await context.runner.store.day(context.day)
        sink.completeActivity(chip)

        guard !log.entries.isEmpty else {
            await stream("Nothing logged \(context.day.isToday ? "today" : "that day") yet.", into: sink)
            return
        }

        let totals = log.totals
        var reply = "\(Self.formatted(totals.calories)) so far, across \(log.entries.count) "
            + (log.entries.count == 1 ? "thing" : "things") + ". "
        reply += "\(Int(totals.protein.rounded()))g protein, "
            + "\(Int(totals.carbs.rounded()))g carbs, "
            + "\(Int(totals.fat.rounded()))g fat."

        if let target = context.profile.calorieTarget {
            let remaining = target - totals.calories
            reply += remaining > 0
                ? " That leaves \(Self.formatted(remaining))."
                : " You're \(Self.formatted(abs(remaining))) past your target."
        }

        await stream(reply, into: sink)
    }

    private func setTarget(_ calories: Double, context: AgentRunContext, sink: AgentSink) async {
        let chip = sink.beginActivity(
            Activity(label: "Noting that down", completedLabel: "Noted", kind: .writing)
        )
        _ = await context.runner.run(
            id: UUID().uuidString,
            name: ToolName.updateProfile.rawValue,
            input: ["calorie_target": .number(calories)]
        )
        sink.completeActivity(chip)
        await stream("Got it — \(Self.formatted(calories)) a day. I'll keep that in mind.", into: sink)
    }

    // MARK: Presentation

    /// Emits a word at a time so the streaming treatment is identical to the model's.
    private func stream(_ text: String, into sink: AgentSink) async {
        for (index, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            sink.appendText(index == 0 ? String(word) : " " + word)
            try? await Task.sleep(for: .milliseconds(22))
        }
    }

    private static func acknowledgement(count: Int) -> String {
        let single = ["Got it.", "Logged.", "Noted.", "In there."]
        let multiple = ["All in.", "Got all of that.", "Logged the lot.", "That's all down."]
        return (count == 1 ? single : multiple).randomElement() ?? "Got it."
    }

    private static let confused = "Tell me what you ate and I'll log it — \"two eggs and toast\" works."

    private static func formatted(_ calories: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: calories)) ?? "\(Int(calories))"
        return "\(number) cal"
    }
}

// MARK: - Intent

enum Intent {
    case log
    case remove(subject: String)
    case status
    case setTarget(Double)

    static func classify(_ text: String) -> Intent {
        let lower = text.lowercased()

        if let target = calorieTarget(in: lower) { return .setTarget(target) }

        for verb in ["remove", "delete", "take off", "undo", "get rid of"] where lower.contains(verb) {
            var subject = lower
            if let range = subject.range(of: verb) { subject.removeSubrange(subject.startIndex..<range.upperBound) }
            // Trim before stripping fillers: "remove the coffee" leaves " the coffee",
            // and a leading space defeats every `hasPrefix` below.
            subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            for filler in ["the ", "that ", "my ", "a ", "an "] where subject.hasPrefix(filler) {
                subject.removeFirst(filler.count)
                break
            }
            return .remove(subject: subject.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let statusPhrases = [
            "how am i", "how many", "how much", "what have i", "what did i", "what's my",
            "whats my", "total", "so far", "left", "remaining", "doing today", "summary"
        ]
        if statusPhrases.contains(where: lower.contains) { return .status }

        return .log
    }

    /// "my target is 2000", "goal: 2200 calories", "aim for 1800 a day"
    static func calorieTarget(in text: String) -> Double? {
        let markers = ["target", "goal", "aim for", "budget"]
        guard markers.contains(where: text.contains) else { return nil }
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
        guard let value = scanner.scanDouble(), value >= 500, value <= 10000 else { return nil }
        return value
    }
}

// MARK: - Phrase parsing

enum FoodPhrase {

    /// Splits "2 eggs, toast and a black coffee" into its three foods.
    static func split(_ text: String) -> [String] {
        var working = text.lowercased()
        for lead in ["i had ", "i ate ", "i just had ", "had ", "ate ", "just had ", "i've had "]
        where working.hasPrefix(lead) {
            working.removeFirst(lead.count)
            break
        }

        for separator in [" and ", " with ", " plus ", " & ", ";", "\n"] {
            working = working.replacingOccurrences(of: separator, with: ",")
        }

        return working
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
    }

    /// Pulls a leading quantity off a phrase: "2 slices of toast" → (2, .slice, "toast").
    ///
    /// The unit is reported separately from the amount, and is nil when the phrase gave
    /// no unit word. That distinction matters: "two eggs" means two of whatever the
    /// database calls one serving of egg, which is better than assuming "pieces".
    static func parse(_ phrase: String) -> (amount: Double?, unit: Quantity.Unit?, food: String) {
        // People write "200g chicken", not "200 g chicken", so a leading token that is
        // a number glued to a unit is split before anything else looks at it.
        var words = phrase.split(separator: " ").flatMap { token -> [String] in
            Self.splitGluedUnit(String(token))
        }
        guard !words.isEmpty else { return (nil, nil, phrase) }

        var amount: Double?
        if let value = number(from: words[0]) {
            amount = value
            let wasArticle = ["a", "an"].contains(words[0])
            words.removeFirst()
            // "a dozen wings", "a couple of eggs": the article is not the count.
            if wasArticle, let next = words.first, let multiple = number(from: next), multiple > 1 {
                amount = multiple
                words.removeFirst()
                if words.first == "of" { words.removeFirst() }
            }
        }

        var unit: Quantity.Unit?
        if let first = words.first, let matched = self.unit(from: first) {
            unit = matched
            words.removeFirst()
            if words.first == "of" { words.removeFirst() }
        }

        let food = words.joined(separator: " ")
        return (amount, unit, food.isEmpty ? phrase : food)
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return "that"
        case 1: return items[0]
        case 2: return "\(items[0]) or \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", or \(items[items.count - 1])"
        }
    }

    static let words: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "half": 0.5, "couple": 2, "few": 3, "several": 3, "dozen": 12
    ]

    static func number(from word: String) -> Double? {
        if let value = Double(word) { return value }
        return words[word]
    }

    static let unitWords: [String: Quantity.Unit] = [
        "cup": .cup, "cups": .cup,
        "bowl": .bowl, "bowls": .bowl,
        "plate": .plate, "plates": .plate,
        "slice": .slice, "slices": .slice,
        "piece": .piece, "pieces": .piece,
        "tbsp": .tablespoon, "tablespoon": .tablespoon, "tablespoons": .tablespoon,
        "tsp": .teaspoon, "teaspoon": .teaspoon, "teaspoons": .teaspoon,
        "g": .gram, "gram": .gram, "grams": .gram,
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "ml": .milliliter,
        "handful": .handful, "handfuls": .handful,
        "scoop": .scoop, "scoops": .scoop,
        "serving": .serving, "servings": .serving, "portion": .serving
    ]

    static func unit(from word: String) -> Quantity.Unit? {
        unitWords[word]
    }

    /// "200g" -> ["200", "g"]. Anything else is returned unchanged.
    static func splitGluedUnit(_ token: String) -> [String] {
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, digits.count < token.count else { return [token] }
        let suffix = String(token.dropFirst(digits.count))
        guard unitWords[suffix] != nil else { return [token] }
        return [String(digits), suffix]
    }
}
