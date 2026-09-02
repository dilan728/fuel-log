import Foundation

/// Nutrition for a specific, concrete amount of food — never "per 100g".
/// Scaling happens at the boundary (`NutritionDatabase`), so by the time facts
/// reach the model layer they describe exactly what was eaten.
struct NutritionFacts: Codable, Hashable, Sendable {
    var calories: Double
    var protein: Double      // g
    var carbs: Double        // g
    var fat: Double          // g
    var fiber: Double?       // g
    var sugar: Double?       // g
    var sodium: Double?      // mg

    static let zero = NutritionFacts(calories: 0, protein: 0, carbs: 0, fat: 0)

    init(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
    }

    /// Multiplies every value. Used to turn a per-serving row into an as-eaten amount.
    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            fiber: fiber.map { $0 * factor },
            sugar: sugar.map { $0 * factor },
            sodium: sodium.map { $0 * factor }
        )
    }

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fiber: sumOptional(lhs.fiber, rhs.fiber),
            sugar: sumOptional(lhs.sugar, rhs.sugar),
            sodium: sumOptional(lhs.sodium, rhs.sodium)
        )
    }

    private static func sumOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (nil, nil): return nil
        default: return (a ?? 0) + (b ?? 0)
        }
    }

    /// Calories accounted for by the three macros, using Atwater factors.
    /// Used to sanity-check model- or database-supplied numbers.
    var macroCalories: Double { protein * 4 + carbs * 4 + fat * 9 }

    /// Fraction of energy from each macro. Drives the ring.
    /// Falls back to an even split rather than dividing by zero.
    var energySplit: (protein: Double, carbs: Double, fat: Double) {
        let total = macroCalories
        guard total > 1 else { return (0, 0, 0) }
        return (protein * 4 / total, carbs * 4 / total, fat * 9 / total)
    }
}

/// How much we trust the numbers. Surfaced in the UI as a quiet dot, never a warning —
/// the point is to let someone tighten an estimate if they care, not to nag.
enum Confidence: String, Codable, Hashable, Sendable, CaseIterable {
    /// Matched a database row with an explicit quantity.
    case measured
    /// Matched a database row but the portion was inferred.
    case estimated
    /// No database match; the numbers are the agent's best guess.
    case guessed

    var label: String {
        switch self {
        case .measured: return "Measured"
        case .estimated: return "Estimated"
        case .guessed: return "Rough guess"
        }
    }
}
