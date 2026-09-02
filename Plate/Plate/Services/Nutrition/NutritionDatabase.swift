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
    /// Nutrition for exactly one `serving`.
    var factsPerServing: NutritionFacts

    /// Scales to a requested amount.
    ///
    /// Returns `.measured` only when the requested unit matches the record's own unit,
    /// because that is the only case where the arithmetic is exact rather than an
    /// assumption about what "a bowl" means.
    func facts(for quantity: Quantity) -> (facts: NutritionFacts, confidence: Confidence) {
        if quantity.unit == serving.unit, serving.amount > 0 {
            return (factsPerServing.scaled(by: quantity.amount / serving.amount), .measured)
        }
        // Different unit: treat the amount as a count of servings. "2 bowls of rice"
        // when the record is per-cup is an estimate, and we say so.
        return (factsPerServing.scaled(by: max(quantity.amount, 0.1)), .estimated)
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
            guard fields.count >= 10 else { continue }

            let aliases = fields[1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard let amount = Double(fields[3]),
                  let unit = Quantity.Unit(rawValue: fields[4]),
                  let kcal = Double(fields[5]),
                  let protein = Double(fields[6]),
                  let carbs = Double(fields[7]),
                  let fat = Double(fields[8])
            else { continue }

            let record = FoodRecord(
                name: fields[0],
                aliases: aliases,
                servingLabel: fields[2],
                serving: Quantity(amount: amount, unit: unit),
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

        // Last resort: character trigrams, which tolerate plurals and typos
        // ("brocoli" → "broccoli") without matching unrelated words.
        return trigramSimilarity(needle, candidate) * 0.72
    }

    private static func trigramSimilarity(_ a: String, _ b: String) -> Double {
        let left = trigrams(a)
        let right = trigrams(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = left.intersection(right).count
        return Double(2 * shared) / Double(left.count + right.count)
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
