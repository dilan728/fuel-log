import Foundation

/// A bubble in a day's thread. This is a *display* type — it is what the UI renders.
/// The wire-format transcript the agent replays lives separately in `DayLog.transcript`,
/// because protocol shape and presentation shape genuinely differ (tool results are
/// user-role messages on the wire but are never bubbles on screen).
struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: Role
    /// Rendered text. Grows in place while `state == .streaming`.
    var text: String
    var createdAt: Date
    /// Human-readable notes about what the agent did. Rendered as small chips above
    /// the bubble. Never contains JSON, tool names, or model identifiers.
    var activity: [Activity]
    /// Food cards rendered inline beneath this message, in order.
    var entryIDs: [UUID]
    var state: State

    enum Role: String, Codable, Hashable, Sendable {
        case user
        case agent
        /// System-authored, non-conversational: "You started logging on Aug 3."
        case marker
    }

    enum State: Codable, Hashable, Sendable {
        case complete
        case streaming
        case failed(reason: String)

        var isStreaming: Bool { if case .streaming = self { return true }; return false }
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String = "",
        createdAt: Date = .now,
        activity: [Activity] = [],
        entryIDs: [UUID] = [],
        state: State = .complete
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.activity = activity
        self.entryIDs = entryIDs
        self.state = state
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }
}

/// One line of "what the agent is doing", phrased for a person.
///
/// `AgentTools.activityLabel(for:)` is the only place that produces these, which is
/// what keeps tool plumbing from leaking into the UI.
struct Activity: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Present tense while running: "Looking up chicken shawarma".
    var label: String
    /// Past tense once finished: "Looked up chicken shawarma". Optional — when nil,
    /// the chip just stops pulsing.
    var completedLabel: String?
    var kind: Kind
    var isComplete: Bool

    enum Kind: String, Codable, Hashable, Sendable {
        case thinking       // the model is reasoning, no tool yet
        case lookup         // nutrition database / USDA
        case history        // reading past days
        case writing        // mutating the log
        case imagining      // generating a food image
    }

    init(
        id: UUID = UUID(),
        label: String,
        completedLabel: String? = nil,
        kind: Kind,
        isComplete: Bool = false
    ) {
        self.id = id
        self.label = label
        self.completedLabel = completedLabel
        self.kind = kind
        self.isComplete = isComplete
    }

    var displayLabel: String {
        isComplete ? (completedLabel ?? label) : label
    }
}
