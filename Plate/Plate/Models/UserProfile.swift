import Foundation

/// The little Plate knows about you. Intentionally minimal: enough to make the
/// numbers mean something, not enough to feel like a medical intake form.
struct UserProfile: Codable, Sendable, Equatable {
    var name: String?
    /// Daily energy target. Nil means "just track, don't judge" — the ring then
    /// shows composition only, with no goal arc.
    var calorieTarget: Double?
    /// Grams of protein per day. The one macro most people actually aim at.
    var proteinTarget: Double?
    var hasCompletedOnboarding: Bool
    /// Free text the agent is given verbatim: allergies, diet, what you're going for.
    /// "vegetarian, training for a half marathon, hate cilantro".
    var context: String?
    var createdAt: Date

    init(
        name: String? = nil,
        calorieTarget: Double? = nil,
        proteinTarget: Double? = nil,
        hasCompletedOnboarding: Bool = false,
        context: String? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.context = context
        self.createdAt = createdAt
    }

    /// A compact sentence describing the user, injected into the agent's system prompt.
    /// Returns nil when there is nothing worth saying, so the prompt stays clean.
    var agentBriefing: String? {
        var parts: [String] = []
        if let name, !name.isEmpty { parts.append("Their name is \(name).") }
        if let calorieTarget {
            parts.append("They aim for about \(Int(calorieTarget)) calories a day.")
        }
        if let proteinTarget {
            parts.append("They aim for about \(Int(proteinTarget))g of protein a day.")
        }
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("In their words: \"\(context)\"")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
