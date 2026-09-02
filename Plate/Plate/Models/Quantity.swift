import Foundation

/// A human-scale amount of food. Deliberately not `Measurement<UnitMass>` — most of
/// what people say is "two eggs" or "a bowl", and forcing that into grams at input
/// time loses the phrasing we want to show back to them.
struct Quantity: Codable, Hashable, Sendable {
    var amount: Double
    var unit: Unit

    enum Unit: String, Codable, Hashable, Sendable, CaseIterable {
        case serving, piece, slice, cup, tablespoon, teaspoon
        case gram, ounce, milliliter, fluidOunce
        case bowl, plate, handful, scoop

        /// Singular / plural display forms. `nil` singular means the unit is implied
        /// and shouldn't be printed at all ("2 eggs", not "2 pieces of eggs").
        var display: (singular: String?, plural: String?) {
            switch self {
            case .serving: return ("serving", "servings")
            case .piece: return (nil, nil)
            case .slice: return ("slice", "slices")
            case .cup: return ("cup", "cups")
            case .tablespoon: return ("tbsp", "tbsp")
            case .teaspoon: return ("tsp", "tsp")
            case .gram: return ("g", "g")
            case .ounce: return ("oz", "oz")
            case .milliliter: return ("ml", "ml")
            case .fluidOunce: return ("fl oz", "fl oz")
            case .bowl: return ("bowl", "bowls")
            case .plate: return ("plate", "plates")
            case .handful: return ("handful", "handfuls")
            case .scoop: return ("scoop", "scoops")
            }
        }

        /// Units that attach without a space ("200g" not "200 g").
        var isTight: Bool {
            switch self {
            case .gram, .ounce, .milliliter: return true
            default: return false
            }
        }
    }

    static let one = Quantity(amount: 1, unit: .serving)

    /// "2 eggs" → amount 2, unit .piece. "180g" → amount 180, unit .gram.
    var display: String {
        let n = Self.formatAmount(amount)
        let forms = unit.display
        guard let word = amount == 1 ? forms.singular : forms.plural else { return n }
        return unit.isTight ? "\(n)\(word)" : "\(n) \(word)"
    }

    /// Drops trailing zeros and renders common fractions the way a person would say them.
    static func formatAmount(_ value: Double) -> String {
        let fractions: [(Double, String)] = [
            (0.25, "¼"), (0.333, "⅓"), (0.5, "½"), (0.667, "⅔"), (0.75, "¾")
        ]
        let whole = floor(value)
        let frac = value - whole
        if let match = fractions.first(where: { abs(frac - $0.0) < 0.02 }) {
            return whole == 0 ? match.1 : "\(Int(whole))\(match.1)"
        }
        if abs(value.rounded() - value) < 0.01 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
