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

    /// Scored by `KeywordMatch`. Glass wins ties, so "iced coffee" is never a bowl.
    static func infer(from name: String) -> FoodForm {
        let context = KeywordMatch.Context(name)

        func bestScore(_ vocabulary: [String]) -> Int? {
            vocabulary.compactMap { KeywordMatch.score($0, in: context) }.max()
        }

        let glass = bestScore(glassWords)
        let bowl = bestScore(bowlWords)

        switch (glass, bowl) {
        case (nil, nil): return .plate
        case (_?, nil): return .glass
        case (nil, _?): return .bowl
        case (let g?, let b?): return g >= b ? .glass : .bowl
        }
    }
}
