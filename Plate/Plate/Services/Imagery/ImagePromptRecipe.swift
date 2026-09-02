import Foundation

/// The consistency contract for generated food photography.
///
/// A catalog of meals only reads as a catalog if every plate was shot the same way.
/// So the prompt fixes everything except the food itself: one camera angle, one
/// background, one plate, one light direction — and that light direction is the same
/// upper-left key the procedural renderer uses, so generated and procedural images can
/// sit next to each other without the page looking lit from two places at once.
enum ImagePromptRecipe {

    /// Never varied. Changing this invalidates the look of every future image, so it
    /// is written once, here, rather than assembled at call sites.
    private static let style = """
    Shot from directly overhead, centred, on a small matte off-white ceramic plate \
    resting on a warm neutral paper surface. Soft diffused studio light from the upper \
    left with a gentle shadow falling to the lower right. Muted natural colours, subtle \
    film grain, shallow depth of field. Editorial cookbook photography. \
    No cutlery, no napkins, no props, no garnish that was not described, no hands, \
    no text, no watermark, no packaging. Square crop, the plate filling most of the frame.
    """

    static func prompt(for name: String, detail: String?, quantity: Quantity) -> String {
        var subject = name
        if let detail, !detail.isEmpty { subject += ", \(detail)" }

        // Portion is described in words rather than numbers: "3 eggs" tends to produce
        // three plates rather than one plate with three eggs on it.
        let portion = portionPhrase(quantity)

        return """
        A single \(portion) of \(subject), plated as one serving.

        \(style)
        """
    }

    private static func portionPhrase(_ quantity: Quantity) -> String {
        switch quantity.unit {
        case .bowl: return "bowl"
        case .plate, .serving: return "portion"
        case .cup: return quantity.amount > 1.5 ? "generous portion" : "portion"
        case .slice: return quantity.amount > 1.5 ? "few slices" : "slice"
        case .piece: return quantity.amount > 2.5 ? "small pile" : (quantity.amount > 1.5 ? "pair" : "piece")
        case .handful, .scoop: return "small portion"
        case .gram, .ounce, .milliliter, .fluidOunce: return "portion"
        case .tablespoon, .teaspoon: return "small spoonful"
        }
    }
}
