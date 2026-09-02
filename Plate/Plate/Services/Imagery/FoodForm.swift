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
    static func infer(from name: String) -> FoodForm {
        let needle = name.lowercased()

        let glassHit = glassWords.filter { needle.contains($0) }.map(\.count).max()
        let bowlHit = bowlWords.filter { needle.contains($0) }.map(\.count).max()

        switch (glassHit, bowlHit) {
        case (nil, nil): return .plate
        case (let glass?, nil): _ = glass; return .glass
        case (nil, _?): return .bowl
        case (let glass?, let bowl?): return glass >= bowl ? .glass : .bowl
        }
    }
}
