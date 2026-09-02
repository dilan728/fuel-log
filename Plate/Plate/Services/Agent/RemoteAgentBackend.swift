import Foundation

/// The real agent: Claude, with the app's tools.
@MainActor
final class RemoteAgentBackend: AgentBackend {
    /// Cap on model↔tool round trips in a single user turn. Six is far more than any
    /// legitimate exchange needs and stops a malformed loop from running up a bill.
    private static let maxIterations = 6

    private let client: AnthropicClient

    init(apiKey: String) {
        client = AnthropicClient(apiKey: apiKey)
    }

    func run(userText: String, context: AgentRunContext, sink: AgentSink) async {
        var transcript = context.transcript
        transcript.append(.user(userText))

        var produced: [AgentTurn] = [.user(userText)]
        let system = SystemPrompt.full(day: context.day, profile: context.profile)
        let tools = AgentTools.definitions

        sink.beginReply()

        do {
            for _ in 0..<Self.maxIterations {
                var completedTurn: AgentTurn?
                var stopReason: String?
                var chipsByToolID: [String: UUID] = [:]

                for try await event in client.stream(system: system, messages: transcript, tools: tools) {
                    switch event {
                    case .textDelta(let text):
                        sink.appendText(text)

                    case .toolStarted(let id, let name):
                        // The arguments are still streaming, so this chip starts vague
                        // and is refined below once the block closes.
                        let chip = AgentTools.activityLabel(for: name, input: .object([:]))
                        chipsByToolID[id] = sink.beginActivity(chip)

                    case .completed(let turn, let reason):
                        completedTurn = turn
                        stopReason = reason
                    }
                }

                guard let assistantTurn = completedTurn else {
                    throw AnthropicClient.ClientError.malformedStream
                }

                transcript.append(assistantTurn)
                produced.append(assistantTurn)

                let calls = assistantTurn.toolUses
                guard stopReason == "tool_use", !calls.isEmpty else { break }

                // Now that arguments are parsed, say what is actually happening.
                for call in calls {
                    if let chip = chipsByToolID[call.id] {
                        sink.refineActivity(chip, to: AgentTools.activityLabel(for: call.name, input: call.input))
                    }
                }

                // Run every call in this turn concurrently, then return all results in
                // one user message — splitting them across messages teaches the model
                // to stop batching its calls.
                let outcomes = await withTaskGroup(of: (Int, AgentToolRunner.Outcome).self) { group in
                    for (index, call) in calls.enumerated() {
                        let runner = context.runner
                        group.addTask {
                            (index, await runner.run(id: call.id, name: call.name, input: call.input))
                        }
                    }
                    var collected: [(Int, AgentToolRunner.Outcome)] = []
                    for await item in group { collected.append(item) }
                    return collected.sorted { $0.0 < $1.0 }.map(\.1)
                }

                for (call, outcome) in zip(calls, outcomes) {
                    if let chip = chipsByToolID[call.id] { sink.completeActivity(chip) }
                    if !outcome.loggedEntryIDs.isEmpty { sink.attachEntries(outcome.loggedEntryIDs) }
                    if outcome.mutatedLog { sink.logDidChange() }
                }

                let resultTurn = AgentTurn.toolResults(outcomes.map(\.result))
                transcript.append(resultTurn)
                produced.append(resultTurn)
            }

            sink.recordTurns(produced)
            sink.finishReply(error: nil)
        } catch is CancellationError {
            sink.finishReply(error: nil)
        } catch {
            sink.finishReply(error: error)
        }
    }
}
