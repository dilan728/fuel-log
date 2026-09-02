import Foundation

/// Shared keyword scoring for the three things inferred from a food's name: its vessel,
/// its texture, and its colour.
///
/// Two rules, both learned from wrong answers:
///
/// * **Whole words.** Plain `contains` served steak in a glass, because "s-TEA-k"
///   contains "tea". Single-word keys must match a word; multi-word keys match as a phrase.
/// * **The head noun wins.** Dish names lead with their main ingredient, so a match near
///   the front of the name outranks a longer match later. Without this, "Steak and Roast
///   Potatoes" was coloured as a potato, because "potato" is one letter longer than "steak".
enum KeywordMatch {
    /// Bonus for appearing in the first two words of the name. Large enough to beat any
    /// plausible length difference, small enough that a much longer later phrase
    /// ("chicken tikka masala") still wins.
    private static let leadBonus = 8

    struct Context {
        let lowered: String
        let words: Set<String>
        let lead: String

        init(_ name: String) {
            lowered = name.lowercased()
            let cleaned = String(lowered.map { $0.isLetter || $0.isNumber ? $0 : " " })
            let split = cleaned.split(separator: " ").map(String.init)
            words = Set(split)
            lead = split.prefix(2).joined(separator: " ")
        }
    }

    static func score(_ phrase: String, in context: Context) -> Int? {
        let matched = phrase.contains(" ")
            ? context.lowered.contains(phrase)
            : context.words.contains(phrase)
        guard matched else { return nil }
        return phrase.count + (context.lead.contains(phrase) ? leadBonus : 0)
    }

    /// The best-scoring row, or nil when nothing matches.
    static func best<Value>(_ rows: [(value: Value, keys: [String])], in name: String) -> Value? {
        let context = Context(name)
        var winner: (score: Int, value: Value)?
        for row in rows {
            for key in row.keys {
                guard let score = score(key, in: context) else { continue }
                if winner == nil || score > winner!.score {
                    winner = (score, row.value)
                }
            }
        }
        return winner?.value
    }
}
