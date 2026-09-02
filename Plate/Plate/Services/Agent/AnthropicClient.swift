import Foundation
import OSLog

/// Streaming client for the Messages API.
///
/// Hand-rolled rather than pulled in as a dependency: the app needs exactly one
/// endpoint, and an SSE reader over `URLSession.bytes` is smaller than the shim would be.
struct AnthropicClient: Sendable {
    static let model = "claude-opus-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let logger = Logger(subsystem: "com.plate.Plate", category: "Anthropic")

    let apiKey: String
    var session: URLSession = .shared

    /// What the caller sees while a turn streams.
    enum Event: Sendable {
        /// Text arriving for the visible reply.
        case textDelta(String)
        /// A tool call has begun. Emitted as soon as the name is known, so the UI can
        /// show "Looking up…" while the arguments are still streaming in.
        case toolStarted(id: String, name: String)
        /// The whole assistant turn, plus why it stopped. Always the last event.
        case completed(turn: AgentTurn, stopReason: String?)
    }

    enum ClientError: LocalizedError {
        case http(status: Int, message: String)
        case malformedStream

        var errorDescription: String? {
            switch self {
            case .http(let status, let message):
                // Surfaced to the user, so it has to be readable rather than a status code.
                switch status {
                case 401: return "That API key was rejected."
                case 429: return "Rate limited — give it a moment."
                case 500...599: return "Anthropic is having trouble right now."
                default: return message.isEmpty ? "Request failed (\(status))." : message
                }
            case .malformedStream:
                return "The response ended unexpectedly."
            }
        }
    }

    // MARK: Request

    func stream(
        system: String,
        messages: [AgentTurn],
        tools: [JSONValue]
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, messages: messages, tools: tools) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        system: String,
        messages: [AgentTurn],
        tools: [JSONValue],
        emit: (Event) -> Void
    ) async throws {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: JSONValue = [
            "model": .string(Self.model),
            "max_tokens": 8000,
            "stream": true,
            // The system prompt is the stable prefix and is worth caching: it is
            // re-sent on every turn of every day's conversation.
            "system": .array([
                .object([
                    "type": "text",
                    "text": .string(system),
                    "cache_control": .object(["type": "ephemeral"])
                ])
            ]),
            // Adaptive thinking with summaries, so "thinking…" is a real state rather
            // than a spinner over dead air. Effort is deliberately not `high`: this is
            // arithmetic over a lookup table, not a reasoning problem, and low effort
            // keeps replies fast and the tone conversational.
            "thinking": .object(["type": "adaptive", "display": "summarized"]),
            "output_config": .object(["effort": "low"]),
            "tools": .array(tools),
            "messages": .array(messages.map { turn in
                .object([
                    "role": .string(turn.role.rawValue),
                    "content": .array(turn.blocks.map(\.wireJSON))
                ])
            })
        ]

        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var detail = ""
            for try await line in bytes.lines { detail += line }
            Self.logger.error("HTTP \(http.statusCode): \(detail)")
            throw ClientError.http(status: http.statusCode, message: Self.errorMessage(from: detail))
        }

        // MARK: SSE
        //
        // Blocks are accumulated by index. Tool arguments arrive as a stream of JSON
        // *fragments* (`input_json_delta`) that are only parseable once concatenated,
        // which is why partial text is buffered per index rather than parsed as it lands.

        var blocks: [Int: PartialBlock] = [:]
        var stopReason: String?

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { continue }

            switch event["type"]?.string {
            case "content_block_start":
                guard let index = event["index"]?.int, let block = event["content_block"] else { break }
                let partial = PartialBlock(seed: block)
                blocks[index] = partial
                if case .toolUse(let id, let name, _) = ContentBlock.from(wire: block) {
                    emit(.toolStarted(id: id, name: name))
                }

            case "content_block_delta":
                guard let index = event["index"]?.int, let delta = event["delta"] else { break }
                switch delta["type"]?.string {
                case "text_delta":
                    let text = delta["text"]?.string ?? ""
                    blocks[index]?.text += text
                    emit(.textDelta(text))
                case "input_json_delta":
                    blocks[index]?.partialJSON += delta["partial_json"]?.string ?? ""
                case "thinking_delta":
                    blocks[index]?.text += delta["thinking"]?.string ?? ""
                case "signature_delta":
                    blocks[index]?.signature = delta["signature"]?.string ?? ""
                default:
                    break
                }

            case "message_delta":
                if let reason = event["delta"]?["stop_reason"]?.string { stopReason = reason }

            case "error":
                let message = event["error"]?["message"]?.string ?? "Unknown error"
                throw ClientError.http(status: 0, message: message)

            default:
                break
            }
        }

        let ordered = blocks.keys.sorted().compactMap { blocks[$0]?.finish() }
        guard !ordered.isEmpty else { throw ClientError.malformedStream }

        emit(.completed(turn: AgentTurn(role: .assistant, blocks: ordered), stopReason: stopReason))
    }

    /// Accumulates one content block as its deltas arrive.
    private struct PartialBlock {
        let seed: JSONValue
        var text = ""
        var partialJSON = ""
        var signature = ""

        func finish() -> ContentBlock? {
            switch seed["type"]?.string {
            case "text":
                return .text(text)

            case "tool_use":
                // An empty argument stream means a no-argument call, not a failure.
                let input: JSONValue
                if partialJSON.isEmpty {
                    input = .object([:])
                } else if let data = partialJSON.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    input = decoded
                } else {
                    AnthropicClient.logger.error("Unparseable tool arguments: \(partialJSON)")
                    input = .object([:])
                }
                return .toolUse(
                    id: seed["id"]?.string ?? UUID().uuidString,
                    name: seed["name"]?.string ?? "",
                    input: input
                )

            default:
                // Thinking and anything newer: rebuild the block with its accumulated
                // fields so it can be replayed byte-for-byte on the next request.
                guard var object = seed.object else { return .opaque(seed) }
                if object["thinking"] != nil { object["thinking"] = .string(text) }
                if !signature.isEmpty { object["signature"] = .string(signature) }
                return .opaque(.object(object))
            }
        }
    }

    private static func errorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
              let message = decoded["error"]?["message"]?.string
        else { return "" }
        return message
    }
}
