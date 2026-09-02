import Foundation

/// One thing eaten. The atom of the whole app.
struct FoodEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Short, title-cased, no quantity baked in. "Chicken Shawarma Bowl".
    var name: String
    /// Optional qualifier shown under the name. "extra garlic sauce, no rice".
    var detail: String?
    var quantity: Quantity
    /// Nutrition for `quantity` as logged — already scaled.
    var facts: NutritionFacts
    var meal: MealSlot
    var loggedAt: Date
    var confidence: Confidence
    var image: ImageState
    /// Stable seed for the procedural plate render, so a given entry always draws
    /// the same way even before (or instead of) a generated photograph.
    var imageSeed: UInt32
    /// What the agent was told, verbatim. Kept so "make that a large" can re-reason.
    var sourceText: String?

    init(
        id: UUID = UUID(),
        name: String,
        detail: String? = nil,
        quantity: Quantity = .one,
        facts: NutritionFacts,
        meal: MealSlot,
        loggedAt: Date = .now,
        confidence: Confidence = .estimated,
        image: ImageState = .none,
        imageSeed: UInt32? = nil,
        sourceText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.quantity = quantity
        self.facts = facts
        self.meal = meal
        self.loggedAt = loggedAt
        self.confidence = confidence
        self.image = image
        // Derive the seed from the name so the same food looks the same across days.
        self.imageSeed = imageSeed ?? FoodEntry.seed(for: name)
        self.sourceText = sourceText
    }

    /// "2 eggs · Breakfast" — the card subtitle.
    var subtitle: String {
        let quantityText = quantity.display
        return quantityText.isEmpty ? meal.title : "\(quantityText) · \(meal.title)"
    }

    /// Deterministic 32-bit hash of the food name. Not security-sensitive; it only
    /// needs to be stable across launches, which `hashValue` is not.
    static func seed(for name: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in name.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

/// Where a food's picture stands. `imageSeed` always provides a usable render, so
/// there is no "empty" state anywhere in the UI — only "not yet photographed".
enum ImageState: Codable, Hashable, Sendable {
    /// Procedural render only. The resting state when no image backend is configured.
    case none
    /// A generation request is in flight.
    case generating
    /// A generated image exists on disk under this file name in the image cache.
    case ready(fileName: String)
    /// Generation was attempted and failed. We keep the reason for Settings
    /// diagnostics but never show it in the main flow.
    case failed(reason: String)

    var isGenerating: Bool { if case .generating = self { return true }; return false }

    var fileName: String? {
        if case .ready(let name) = self { return name }
        return nil
    }
}

/// Which part of the day a food belongs to. Inferred from the clock unless the
/// user says otherwise, because making people categorize their own food is a chore.
enum MealSlot: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case breakfast, lunch, dinner, snack

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }

    /// Sort order within a day — snacks trail whatever meal they follow, so they sort last.
    private var rank: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }

    static func < (lhs: MealSlot, rhs: MealSlot) -> Bool { lhs.rank < rhs.rank }

    /// The slot a meal logged at `date` most likely belongs to.
    static func inferred(from date: Date, calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}
