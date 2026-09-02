import Foundation

/// What a food is served in.
///
/// Shot from overhead, the vessel is most of what gives an image its shape, so getting
/// this right matters more than getting the colour right. A flat white drawn as solids
/// on a dinner plate is instantly, obviously wrong in a way that a slightly-off brown
/// never is.
enum FoodForm: String, Sendable, Equatable, CaseIterable {
    case plate
    case bowl
    case glass

    var shaderValue: Double {
        switch self {
        case .plate: return 0
        case .bowl: return 1
        case .glass: return 2
        }
    }

    private static let glassWords = [
        "coffee", "latte", "cappuccino", "flat white", "espresso", "americano",
        "macchiato", "mocha", "tea", "chai", "matcha", "juice", "smoothie", "shake",
        "milkshake", "soda", "cola", "coke", "beer", "lager", "ale", "wine", "water",
        "cocktail", "margarita", "mojito", "lemonade", "kombucha", "milk", "cordial",
        "whiskey", "whisky", "vodka", "gin", "spirits", "drink", "brew"
    ]

    private static let bowlWords = [
        "soup", "stew", "broth", "cereal", "oatmeal", "porridge", "oats", "yogurt",
        "yoghurt", "ramen", "pho", "udon", "noodle", "chili", "chilli", "curry",
        "salad", "poke", "bowl", "granola", "muesli", "ice cream", "gelato", "pudding",
        "congee", "dal", "daal", "risotto", "chowder", "hummus", "guacamole", "salsa",
        "edamame", "berries", "fruit", "beans", "lentils", "quinoa", "couscous"
    ]

    /// Longest match wins, and glass is checked first — "green smoothie bowl" is a
    /// bowl, but "iced coffee" should never be one.
    ///
    /// Matching is on whole words. Plain `contains` served steak in a glass, because
    /// "s-TEA-k" contains "tea".
    static func infer(from name: String) -> FoodForm {
        let lowered = name.lowercased()
        let cleaned = String(lowered.map { $0.isLetter || $0.isNumber ? $0 : " " })
        let words = Set(cleaned.split(separator: " ").map(String.init))

        func longestMatch(in vocabulary: [String]) -> Int? {
            var best: Int?
            for phrase in vocabulary {
                // Multi-word entries ("flat white") match as a phrase; single words
                // must match a whole word.
                let hit = phrase.contains(" ") ? lowered.contains(phrase) : words.contains(phrase)
                guard hit else { continue }
                best = max(best ?? 0, phrase.count)
            }
            return best
        }

        let glassHit = longestMatch(in: glassWords)
        let bowlHit = longestMatch(in: bowlWords)

        switch (glassHit, bowlHit) {
        case (nil, nil): return .plate
        case (let glass?, nil): _ = glass; return .glass
        case (nil, _?): return .bowl
        case (let glass?, let bowl?): return glass >= bowl ? .glass : .bowl
        }
    }
}
