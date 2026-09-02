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

    private static let table: [(keys: [String], primary: UInt32, secondary: UInt32)] = [
        // Greens
        (["salad", "spinach", "kale", "broccoli", "pesto", "guacamole", "avocado",
          "edamame", "green bean", "asparagus", "cucumber", "lettuce", "arugula",
          "pea", "zucchini", "matcha", "brussels"], 0x6E8F4A, 0x9DBE6B),
        // Reds / tomato
        (["tomato", "marinara", "pizza", "strawberry", "raspberry", "beet",
          "watermelon", "salsa", "chili", "pepperoni", "ketchup", "cherry"], 0xB63A2C, 0xD9614A),
        // Browns / roasted / meat
        (["steak", "beef", "burger", "brisket", "meatball", "sausage", "bacon",
          "roast", "gravy", "mushroom", "chocolate", "coffee", "brownie",
          "pork", "lamb", "barbecue", "bbq", "shawarma", "kebab"], 0x6B4128, 0x9A6238),
        // Golden / fried / bread / grain
        (["bread", "toast", "bagel", "fries", "chicken", "waffle", "pancake",
          "croissant", "cracker", "cereal", "granola", "tortilla", "taco",
          "burrito", "sandwich", "wrap", "pastry", "muffin", "donut",
          "cookie", "biscuit", "falafel", "tempura", "schnitzel"], 0xC08A3E, 0xE0B268),
        // Pale / dairy / rice / pasta
        (["rice", "pasta", "noodle", "yogurt", "milk", "cheese", "egg",
          "tofu", "oat", "porridge", "hummus", "potato", "dumpling",
          "ramen", "risotto", "quinoa", "couscous"], 0xD6C3A0, 0xEFE3C8),
        // Orange
        (["carrot", "sweet potato", "pumpkin", "squash", "mango", "peach",
          "apricot", "orange", "salmon", "curry", "paprika"], 0xC96A24, 0xE79449),
        // Purple / berry
        (["blueberry", "blackberry", "grape", "eggplant", "aubergine",
          "plum", "fig", "acai", "cabbage"], 0x5A3B6B, 0x8A5FA0),
        // Greens-pale / fruit
        (["apple", "pear", "kiwi", "lime", "melon", "grape"], 0x8FA84E, 0xC2D186),
        // Yellows
        (["banana", "corn", "lemon", "mustard", "pineapple", "butter",
          "omelette", "custard"], 0xD9B03C, 0xF0D477),
        // Drinks — coffee family. Dark liquid, pale crema.
        (["coffee", "espresso", "americano", "latte", "cappuccino", "flat white",
          "macchiato", "mocha", "cold brew"], 0x4A2E1E, 0xB98E63),
        (["tea", "chai", "kombucha"], 0x9A6B33, 0xC79A5E),
        (["milk", "milkshake", "horchata"], 0xF0EAE0, 0xFFFFFF),
        (["beer", "lager", "ale", "cider"], 0xC98A1E, 0xE8B84B),
        (["wine", "sangria"], 0x6E1F2E, 0x9E3A4C),
        (["water", "sparkling water", "soda water"], 0xD8E4E8, 0xF0F6F8),
        (["cola", "coke", "root beer"], 0x3A2118, 0x6B3E28),
        (["lemonade", "orange juice", "juice"], 0xE0A62A, 0xF5CE68)
    ]

    /// Longest-match wins, so "sweet potato" beats "potato" and "chicken salad"
    /// resolves to salad-green only if "salad" appears later in the name than "chicken".
    static func forFood(_ name: String) -> FoodPalette {
        let needle = name.lowercased()
        var best: (length: Int, primary: UInt32, secondary: UInt32)?

        for row in table {
            for key in row.keys where needle.contains(key) {
                if best == nil || key.count > best!.length {
                    best = (key.count, row.primary, row.secondary)
                }
            }
        }

        guard let best else { return neutral(for: name) }
        return FoodPalette(
            primary: Palette.dynamic(light: best.primary, dark: lighten(best.primary)),
            secondary: Palette.dynamic(light: best.secondary, dark: lighten(best.secondary)),
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
