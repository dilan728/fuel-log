import Foundation

/// One row of the bundled table.
struct FoodRecord: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var aliases: [String]
    /// How the serving is described to a person: "large egg", "cup cooked".
    var servingLabel: String
    /// The serving this record's numbers describe.
    var serving: Quantity
    /// Approximate mass of one `serving`, in grams. What makes "200g of chicken"
    /// convertible rather than two hundred servings of chicken.
    var servingGrams: Double
    /// Nutrition for exactly one `serving`.
    var factsPerServing: NutritionFacts

    /// Scales to a requested amount, in four cases of decreasing certainty.
    func facts(for quantity: Quantity) -> (facts: NutritionFacts, confidence: Confidence) {
        // 1. Same unit: an exact ratio.
        if quantity.unit == serving.unit, serving.amount > 0 {
            return (factsPerServing.scaled(by: quantity.amount / serving.amount), .measured)
        }

        // 2. A mass or volume, converted through the serving's known mass. Without this
        //    step "200g chicken" multiplied a serving by two hundred.
        if let requested = quantity.grams, servingGrams > 0 {
            return (factsPerServing.scaled(by: requested / servingGrams), .measured)
        }

        // 3. A count against a count-like serving: "3 slices" of a per-slice row.
        if quantity.unit.isCountLike, serving.unit.isCountLike, serving.amount > 0 {
            return (factsPerServing.scaled(by: quantity.amount / serving.amount), .estimated)
        }

        // 4. Otherwise the amount is a number of servings — "2 bowls" of a per-cup row.
        //    Clamped, because an unbounded multiplier here is how a day ends up with
        //    forty thousand calories in it.
        return (factsPerServing.scaled(by: min(max(quantity.amount, 0.1), 12)), .estimated)
    }
}

/// A scored search hit.
struct FoodMatch: Identifiable, Hashable, Sendable {
    var id: String { record.id }
    var record: FoodRecord
    /// 0…1. Above `NutritionDatabase.confidentThreshold` we treat it as a real match.
    var score: Double
}

/// Lookup over the bundled table.
///
/// Deliberately not a fuzzy-search library. Food names are short, and the failure mode
/// that matters is matching the *wrong* food confidently — so scoring is conservative
/// and exposes its confidence rather than always returning a best guess.
final class NutritionDatabase: Sendable {
    static let shared = NutritionDatabase()

    /// Below this, a match is offered as a suggestion but never auto-applied.
    static let confidentThreshold = 0.62

    let records: [FoodRecord]
    /// Normalised name/alias → record index, for the exact-match fast path.
    private let exactIndex: [String: Int]

    init(raw: String = NutritionTable.raw) {
        var records: [FoodRecord] = []
        var index: [String: Int] = [:]

        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard fields.count >= 11 else { continue }

            let aliases = fields[1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard let amount = Double(fields[3]),
                  let unit = Quantity.Unit(rawValue: fields[4]),
                  let kcal = Double(fields[5]),
                  let protein = Double(fields[6]),
                  let carbs = Double(fields[7]),
                  let fat = Double(fields[8]),
                  let grams = Double(fields[10])
            else { continue }

            let record = FoodRecord(
                name: fields[0],
                aliases: aliases,
                servingLabel: fields[2],
                serving: Quantity(amount: amount, unit: unit),
                servingGrams: grams,
                factsPerServing: NutritionFacts(
                    calories: kcal,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    fiber: Double(fields[9])
                )
            )

            let position = records.count
            records.append(record)
            for key in [record.name] + record.aliases {
                index[Self.normalize(key)] = position
            }
        }

        self.records = records
        self.exactIndex = index
    }

    // MARK: Search

    func search(_ query: String, limit: Int = 5) -> [FoodMatch] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return [] }

        if let position = exactIndex[needle] {
            return [FoodMatch(record: records[position], score: 1.0)]
        }

        let needleTokens = Set(needle.split(separator: " ").map(String.init))
        var scored: [FoodMatch] = []

        for record in records {
            var best = 0.0
            for candidate in [record.name] + record.aliases {
                best = max(best, Self.score(needle: needle, needleTokens: needleTokens, candidate: candidate))
                if best >= 0.99 { break }
            }
            if best > 0.3 {
                scored.append(FoodMatch(record: record, score: best))
            }
        }

        return scored
            .sorted {
                // Ties broken toward the shorter name: "Egg" should beat
                // "Scrambled Eggs" for the query "egg".
                $0.score == $1.score ? $0.record.name.count < $1.record.name.count : $0.score > $1.score
            }
            .prefix(limit)
            .map { $0 }
    }

    /// The single best match, or nil when nothing clears the confidence bar.
    func bestMatch(_ query: String) -> FoodMatch? {
        search(query, limit: 1).first.flatMap { $0.score >= Self.confidentThreshold ? $0 : nil }
    }

    // MARK: Scoring

    private static func score(needle: String, needleTokens: Set<String>, candidate raw: String) -> Double {
        let candidate = normalize(raw)
        if candidate == needle { return 1.0 }

        // Whole-candidate containment, weighted by how much of the query it explains.
        // "chicken" inside "chicken breast" scores well; "a" inside "avocado" does not.
        if needle.contains(candidate) {
            return 0.72 + 0.22 * (Double(candidate.count) / Double(max(needle.count, 1)))
        }
        if candidate.contains(needle) {
            return 0.70 + 0.22 * (Double(needle.count) / Double(max(candidate.count, 1)))
        }

        let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
        let shared = needleTokens.intersection(candidateTokens)
        if !shared.isEmpty {
            let union = needleTokens.union(candidateTokens).count
            let jaccard = Double(shared.count) / Double(max(union, 1))
            // Token overlap alone tops out below the confident threshold: sharing the
            // word "chicken" is a lead, not an answer.
            return 0.34 + 0.28 * jaccard
        }

        // Last resort: two typo measures, because they fail on different mistakes.
        //
        // Trigrams handle plurals and dropped letters ("brocoli" → "broccoli") but are
        // weak against a substitution in the middle of a word: "avacado" vs "avocado"
        // differ by one letter and share only four of seven trigrams, because the wrong
        // letter spoils the three trigrams containing it. Edit distance catches exactly
        // that case. Whichever is more confident wins.
        return max(
            trigramSimilarity(needle, candidate) * 0.80,
            editSimilarity(needle, candidate) * 0.78
        )
    }

    private static func trigramSimilarity(_ a: String, _ b: String) -> Double {
        let left = trigrams(a)
        let right = trigrams(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = left.intersection(right).count
        return Double(2 * shared) / Double(left.count + right.count)
    }

    /// 1 for identical, falling off with each edit. Returns 0 unless the strings are a
    /// plausible typo of one another — at most two edits apart and similar in length —
    /// which also keeps the O(n·m) table small enough to run against every row.
    private static func editSimilarity(_ a: String, _ b: String) -> Double {
        let left = Array(a)
        let right = Array(b)
        guard !left.isEmpty, !right.isEmpty, abs(left.count - right.count) <= 2 else { return 0 }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            var rowMinimum = i
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
                rowMinimum = min(rowMinimum, current[j])
            }
            // Every remaining row can only add to the distance, so once the best cell in
            // a row exceeds the budget the answer is already too far away.
            if rowMinimum > 2 { return 0 }
            swap(&previous, &current)
        }

        let distance = previous[right.count]
        guard distance <= 2 else { return 0 }
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }

    private static func trigrams(_ text: String) -> Set<String> {
        let padded = " \(text) "
        let characters = Array(padded)
        guard characters.count >= 3 else { return [padded] }
        return Set((0...(characters.count - 3)).map { String(characters[$0..<($0 + 3)]) })
    }

    /// Lowercase, strip diacritics and punctuation, collapse whitespace, and drop the
    /// filler words people put in food names.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let cleaned = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        let stopWords: Set<String> = ["a", "an", "the", "of", "some", "with", "and", "my"]
        return String(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
            .joined(separator: " ")
    }
}
