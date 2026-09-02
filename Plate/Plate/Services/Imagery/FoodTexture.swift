import SwiftUI
import UIKit
import simd

/// How a food is *shaped*, as distinct from what it is served in.
///
/// This is what stops every dish from being the same pile of pebbles in a different
/// colour. Rice is many small grains; a steak is a slab; salad is thin tilted leaves;
/// toast is bread with something on it; coffee is a liquid surface. Those read as
/// completely different photographs before colour is applied at all.
enum FoodTexture: String, Sendable, CaseIterable {
    /// Loose pieces — stew, roast vegetables, meatballs, a muffin.
    case chunks
    /// Many small pieces — rice, oats, nuts, berries.
    case grains
    /// Thin tilted sheets — salad, spinach, cured meat.
    case leaves
    /// A base with a topping on it — toast, pizza, a sandwich.
    case topped
    /// A single solid piece — a steak, a bar of chocolate, a slice of cake.
    case slab
    /// A surface — coffee, soup, yoghurt, sauce.
    case liquid

    var shaderValue: Int32 {
        switch self {
        case .chunks: return 0
        case .grains: return 1
        case .leaves: return 2
        case .topped: return 3
        case .liquid: return 4
        case .slab: return 5
        }
    }

    var pieceCount: Int32 {
        switch self {
        case .chunks: return 5
        case .grains: return 22
        case .leaves: return 11
        case .topped: return 2
        case .slab: return 1
        case .liquid: return 0
        }
    }

    /// GGX roughness. Sauce and fruit are glossy; bread and grains are not.
    var roughness: Float {
        switch self {
        case .chunks: return 0.34
        case .grains: return 0.55
        case .leaves: return 0.28
        case .topped: return 0.44
        case .slab: return 0.40
        case .liquid: return 0.09
        }
    }

    /// How much light passes through. Bread, fruit and leaves are translucent at the
    /// edges; a hard terminator on them reads as plastic.
    var subsurface: Float {
        switch self {
        case .chunks: return 0.18
        case .grains: return 0.22
        case .leaves: return 0.58
        case .topped: return 0.36
        case .slab: return 0.30
        case .liquid: return 0.0
        }
    }

    private static let table: [(value: FoodTexture, keys: [String])] = [
        (.liquid, ["coffee", "espresso", "americano", "latte", "cappuccino", "flat white",
                   "macchiato", "mocha", "tea", "chai", "juice", "smoothie", "shake",
                   "milkshake", "soda", "cola", "coke", "beer", "lager", "wine", "water",
                   "cocktail", "margarita", "mojito", "lemonade", "milk", "whiskey",
                   "vodka", "gin", "soup", "broth", "chowder", "gravy", "yogurt",
                   "yoghurt", "greek yogurt", "pudding", "custard", "honey", "syrup",
                   "oil", "sauce", "ketchup", "mayonnaise", "hummus", "dressing", "salsa"]),
        (.grains, ["rice", "quinoa", "couscous", "oatmeal", "porridge", "oats", "granola",
                   "muesli", "cereal", "peas", "corn", "beans", "lentils", "chickpeas",
                   "edamame", "nuts", "almonds", "peanuts", "cashews", "walnuts",
                   "pistachios", "raisins", "berries", "blueberries", "raspberries",
                   "strawberries", "popcorn", "seeds", "sugar", "trail mix", "olives",
                   "pretzels", "chips", "crisps", "fries"]),
        (.leaves, ["salad", "spinach", "kale", "lettuce", "arugula", "cabbage", "coleslaw",
                   "greens", "herbs", "basil", "slaw", "seaweed", "bacon", "prosciutto",
                   "ham", "smoked salmon", "sashimi", "carpaccio"]),
        (.topped, ["toast", "bread", "bagel", "pizza", "sandwich", "wrap", "burrito",
                   "taco", "quesadilla", "pancake", "waffle", "tortilla", "naan", "pita",
                   "cracker", "lasagna", "french toast", "grilled cheese", "avocado toast",
                   "nachos", "bruschetta", "blt"]),
        (.slab, ["steak", "salmon", "cod", "tuna", "fillet", "chop", "meatloaf",
                 "schnitzel", "omelette", "omelet", "chocolate", "brownie", "cake",
                 "cheesecake", "cookie", "biscuit", "pie", "burger", "cheeseburger",
                 "hamburger", "rice cake", "tofu", "tempeh", "halloumi", "frittata"])
    ]

    static func infer(from name: String) -> FoodTexture {
        // `.chunks` is the right default: stews, curries, roasts and pasta are all piles.
        KeywordMatch.best(table, in: name) ?? .chunks
    }
}

/// Everything the renderer needs to draw one dish.
struct FoodSceneRecipe: Hashable, Sendable {
    var seed: UInt32
    var vessel: FoodForm
    var texture: FoodTexture
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var ground: SIMD4<Float>
    var base: SIMD4<Float>

    init(food name: String, seed: UInt32? = nil) {
        self.seed = seed ?? FoodEntry.seed(for: name)
        self.vessel = .infer(from: name)
        self.texture = .infer(from: name)

        let palette = FoodPalette.forFood(name)
        // Always resolved light. A photograph does not change when the app theme does,
        // and the render is cached once for both appearances.
        self.primary = Self.renderable(palette.primary)
        self.secondary = Self.renderable(palette.secondary)
        self.ground = Self.renderable(FoodPalette.studioGround)
        self.base = Self.renderable(FoodPalette.breadBase)
    }

    /// sRGB → linear, pulled toward the middle on the way.
    ///
    /// The palette is tuned for flat 2D fills. Run through a physical shading model and
    /// a filmic tonemap, those same values come out lurid — the first render had a
    /// highlighter-green avocado and a fire-engine tomato. Real food occupies a narrow,
    /// unsaturated band.
    private static func renderable(_ color: Color) -> SIMD4<Float> {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)

        func toLinear(_ c: CGFloat) -> Float {
            let v = Float(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        var rgb = SIMD3(toLinear(r), toLinear(g), toLinear(b))

        let luminance = dot(rgb, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        rgb = simd_mix(SIMD3(repeating: luminance), rgb, SIMD3<Float>(repeating: 0.80))
        rgb = simd_clamp(rgb, SIMD3(repeating: 0.020), SIMD3(repeating: 0.82))

        return SIMD4(rgb.x, rgb.y, rgb.z, 1)
    }
}
