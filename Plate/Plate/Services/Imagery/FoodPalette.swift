import SwiftUI

/// The colours a food is drawn in.
///
/// Used by the procedural renderer (and as the placeholder tint behind a generated
/// photograph). This is a small, honest keyword table rather than anything clever:
/// the goal is only that pesto reads green and a burger reads brown, which a lookup
/// gets right far more reliably than any hue derived from hashing the name.
struct FoodPalette: Equatable, Sendable {
    var primary: Color
    var secondary: Color
    var ground: Color

    /// Warm neutral studio backdrop — the constant that makes every plate in the
    /// catalog look like it was shot in the same room.
    static let studioGround = Palette.dynamic(light: 0xF2EBE0, dark: 0x2A2622)

    /// Bread, dough, pastry. The thing a topping sits on. Kept separate from the food
    /// palette because a pizza's base is crust-coloured, not tomato-coloured, and the
    /// first render made both layers red.
    static let breadBase = Palette.dynamic(light: 0xCBA372, dark: 0xCBA372)

    private static let table: [(value: (primary: UInt32, secondary: UInt32), keys: [String])] = [
        // Greens
        ((primary: 0x6E8F4A, secondary: 0x9DBE6B), keys: ["salad", "spinach", "kale", "broccoli", "pesto", "guacamole", "avocado",
          "edamame", "green bean", "asparagus", "cucumber", "lettuce", "arugula",
          "pea", "zucchini", "matcha", "brussels"]),
        // Reds / tomato
        ((primary: 0xB63A2C, secondary: 0xD9614A), keys: ["tomato", "marinara", "pizza", "strawberry", "raspberry", "beet",
          "watermelon", "salsa", "chili", "pepperoni", "ketchup", "cherry"]),
        // Browns / roasted / meat
        ((primary: 0x6B4128, secondary: 0x9A6238), keys: ["steak", "beef", "burger", "brisket", "meatball", "sausage", "bacon",
          "roast", "gravy", "mushroom", "chocolate", "coffee", "brownie",
          "pork", "lamb", "barbecue", "bbq", "shawarma", "kebab"]),
        // Golden / fried / bread / grain
        ((primary: 0xC08A3E, secondary: 0xE0B268), keys: ["bread", "toast", "bagel", "fries", "chicken", "waffle", "pancake",
          "croissant", "cracker", "cereal", "granola", "tortilla", "taco",
          "burrito", "sandwich", "wrap", "pastry", "muffin", "donut",
          "cookie", "biscuit", "falafel", "tempura", "schnitzel"]),
        // Pale / dairy / rice / pasta
        ((primary: 0xD6C3A0, secondary: 0xEFE3C8), keys: ["rice", "pasta", "noodle", "yogurt", "milk", "cheese", "egg",
          "tofu", "oat", "porridge", "hummus", "potato", "dumpling",
          "ramen", "risotto", "quinoa", "couscous"]),
        // Orange
        ((primary: 0xC96A24, secondary: 0xE79449), keys: ["carrot", "sweet potato", "pumpkin", "squash", "mango", "peach",
          "apricot", "orange", "salmon", "curry", "paprika"]),
        // Purple / berry
        ((primary: 0x5E4869, secondary: 0x8E7A9C), keys: ["blueberry", "blueberries", "blackberry", "grape", "eggplant", "aubergine",
          "plum", "fig", "acai", "cabbage"]),
        // Greens-pale / fruit
        ((primary: 0x8FA84E, secondary: 0xC2D186), keys: ["apple", "pear", "kiwi", "lime", "melon", "grape"]),
        // Yellows
        ((primary: 0xD9B03C, secondary: 0xF0D477), keys: ["banana", "corn", "lemon", "mustard", "pineapple", "butter",
          "omelette", "custard"]),
        // Nuts. Without these they fell through to the amber default and rendered olive.
        ((primary: 0x9A7247, secondary: 0xC7A377), keys: ["almond", "almonds", "cashew", "cashews",
          "walnut", "walnuts", "peanut", "peanuts", "pistachio", "pistachios", "nuts",
          "pecan", "hazelnut", "trail mix"]),
        // Drinks — coffee family. Dark liquid, pale crema.
        ((primary: 0x63412A, secondary: 0xC29A72), keys: ["coffee", "espresso", "americano", "latte", "cappuccino", "flat white",
          "macchiato", "mocha", "cold brew"]),
        ((primary: 0x9A6B33, secondary: 0xC79A5E), keys: ["tea", "chai", "kombucha"]),
        ((primary: 0xF0EAE0, secondary: 0xFFFFFF), keys: ["milk", "milkshake", "horchata"]),
        ((primary: 0xC98A1E, secondary: 0xE8B84B), keys: ["beer", "lager", "ale", "cider"]),
        ((primary: 0x6E1F2E, secondary: 0x9E3A4C), keys: ["wine", "sangria"]),
        ((primary: 0xD8E4E8, secondary: 0xF0F6F8), keys: ["water", "sparkling water", "soda water"]),
        ((primary: 0x3A2118, secondary: 0x6B3E28), keys: ["cola", "coke", "root beer"]),
        ((primary: 0xE0A62A, secondary: 0xF5CE68), keys: ["lemonade", "orange juice", "juice"])
    ]

    /// Scored by `KeywordMatch`: whole words only, and the head noun of the dish wins.
    /// "Steak and Roast Potatoes" is a steak dish, even though "potato" is the longer word.
    static func forFood(_ name: String) -> FoodPalette {
        guard let match = KeywordMatch.best(table, in: name) else { return neutral(for: name) }
        return FoodPalette(
            primary: Palette.dynamic(light: match.primary, dark: lighten(match.primary)),
            secondary: Palette.dynamic(light: match.secondary, dark: lighten(match.secondary)),
            ground: studioGround
        )
    }

    /// Unrecognised foods get a warm neutral varied slightly by name, so a plate of
    /// something unknown still differs from the plate next to it.
    private static func neutral(for name: String) -> FoodPalette {
        let seed = FoodEntry.seed(for: name)
        let jitter = Double(seed % 40) / 40.0            // 0…1
        let hue = 0.07 + jitter * 0.05                   // amber → ochre
        return FoodPalette(
            primary: Color(hue: hue, saturation: 0.44, brightness: 0.52),
            secondary: Color(hue: hue + 0.02, saturation: 0.36, brightness: 0.72),
            ground: studioGround
        )
    }

    /// Dark-mode variant: food should stay recognisably itself, just lifted off a
    /// darker ground, so we raise brightness without desaturating.
    private static func lighten(_ hex: UInt32) -> UInt32 {
        let r = min(255, Int(Double((hex >> 16) & 0xFF) * 1.22 + 14))
        let g = min(255, Int(Double((hex >> 8) & 0xFF) * 1.22 + 14))
        let b = min(255, Int(Double(hex & 0xFF) * 1.22 + 14))
        return UInt32(r << 16 | g << 8 | b)
    }
}
