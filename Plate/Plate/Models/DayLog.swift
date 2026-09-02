import Foundation

/// Everything about one day: what was eaten, and the conversation that produced it.
struct DayLog: Codable, Identifiable, Sendable {
    var id: DayID
    var entries: [FoodEntry]
    /// What the UI renders.
    var messages: [ChatMessage]
    /// What the agent replays to the API. Written only by `AgentEngine`.
    var transcript: [AgentTurn]
    var updatedAt: Date

    init(
        id: DayID,
        entries: [FoodEntry] = [],
        messages: [ChatMessage] = [],
        transcript: [AgentTurn] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.entries = entries
        self.messages = messages
        self.transcript = transcript
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool { entries.isEmpty && messages.isEmpty }

    var totals: NutritionFacts {
        entries.reduce(.zero) { $0 + $1.facts }
    }

    /// Entries grouped into meal sections, each sorted by clock time. Empty slots
    /// are omitted — the app never shows an empty "Lunch" header.
    var byMeal: [(slot: MealSlot, entries: [FoodEntry])] {
        Dictionary(grouping: entries, by: \.meal)
            .map { (slot: $0.key, entries: $0.value.sorted { $0.loggedAt < $1.loggedAt }) }
            .sorted { $0.slot < $1.slot }
    }

    func entry(_ id: UUID) -> FoodEntry? {
        entries.first { $0.id == id }
    }

    /// Chronological, for the catalog.
    var entriesInOrder: [FoodEntry] {
        entries.sorted { $0.loggedAt < $1.loggedAt }
    }
}
