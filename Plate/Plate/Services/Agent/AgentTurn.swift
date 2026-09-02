import Foundation

/// One message exactly as it appears on the wire.
///
/// Kept separate from `ChatMessage` because the two shapes genuinely differ: tool
/// results are `user`-role messages the UI must never render, and assistant turns can
/// carry thinking blocks that have to be replayed unmodified.
struct AgentTurn: Codable, Hashable, Sendable {
    enum Role: String, Codable, Hashable, Sendable {
        case user, assistant
    }

    var role: Role
    var blocks: [ContentBlock]

    static func user(_ text: String) -> AgentTurn {
        AgentTurn(role: .user, blocks: [.text(text)])
    }

    static func toolResults(_ results: [ToolResult]) -> AgentTurn {
        AgentTurn(
            role: .user,
            blocks: results.map {
                .toolResult(toolUseID: $0.toolUseID, content: $0.content, isError: $0.isError)
            }
        )
    }

    /// All text across the turn, joined. Used for display fallbacks and for the
    /// local backend, which has no block structure of its own.
    var plainText: String {
        blocks.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
            .joined(separator: "\n")
    }

    var toolUses: [(id: String, name: String, input: JSONValue)] {
        blocks.compactMap {
            if case .toolUse(let id, let name, let input) = $0 { return (id, name, input) }
            return nil
        }
    }
}

/// A block within a turn.
///
/// `.opaque` is load-bearing: the API returns block types we do not model (thinking
/// blocks, and whatever ships next), and those must go back out byte-identically or
/// the request is rejected. Storing the raw JSON is the only way to guarantee that
/// without chasing every new block type.
enum ContentBlock: Codable, Hashable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    case opaque(JSONValue)

    /// The wire representation.
    var wireJSON: JSONValue {
        switch self {
        case .text(let text):
            return ["type": "text", "text": .string(text)]
        case .toolUse(let id, let name, let input):
            return ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]
        case .toolResult(let toolUseID, let content, let isError):
            return [
                "type": "tool_result",
                "tool_use_id": .string(toolUseID),
                "content": .string(content),
                "is_error": .bool(isError)
            ]
        case .opaque(let raw):
            return raw
        }
    }

    /// Parses a block from an API response, preserving anything unrecognised.
    static func from(wire: JSONValue) -> ContentBlock {
        switch wire["type"]?.string {
        case "text":
            return .text(wire["text"]?.string ?? "")
        case "tool_use":
            return .toolUse(
                id: wire["id"]?.string ?? UUID().uuidString,
                name: wire["name"]?.string ?? "",
                input: wire["input"] ?? .object([:])
            )
        default:
            return .opaque(wire)
        }
    }
}

/// The result of running one tool, ready to be sent back.
struct ToolResult: Sendable, Hashable {
    var toolUseID: String
    var content: String
    var isError: Bool

    init(toolUseID: String, content: String, isError: Bool = false) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
    }
}
