import Foundation

/// Where the agent's replies come from.
///
/// Two implementations: `RemoteAgentBackend` (the real model) and `LocalAgentBackend`
/// (a genuine parser, no network). Both drive the same `AgentSink`, so the UI is
/// identical either way — including the activity chips, which the local backend also
/// produces because it really does perform lookups and writes.
@MainActor
protocol AgentBackend {
    func run(userText: String, context: AgentRunContext, sink: AgentSink) async
}

struct AgentRunContext: Sendable {
    var day: DayID
    var profile: UserProfile
    /// Prior turns in wire form. The local backend ignores this.
    var transcript: [AgentTurn]
    var runner: AgentToolRunner
}

/// What a backend reports as it works.
///
/// Every method is main-actor: these drive view state directly, and the alternative —
/// hopping actors per token — showed up as visible stutter in the streaming text.
@MainActor
protocol AgentSink: AnyObject {
    /// A new assistant bubble has begun.
    func beginReply()
    /// Text for the current bubble.
    func appendText(_ text: String)
    /// Show an activity chip. Returns an id used to complete it.
    func beginActivity(_ activity: Activity) -> UUID
    func completeActivity(_ id: UUID)
    /// Replace a chip's wording once better information arrives. Tool arguments stream
    /// in after the tool's name does, so the first label is necessarily vague.
    func refineActivity(_ id: UUID, to activity: Activity)
    /// Attach food cards under the current bubble.
    func attachEntries(_ ids: [UUID])
    /// The day's contents changed on disk and should be re-read.
    func logDidChange()
    /// The turn is over. `error` is nil on success.
    func finishReply(error: Error?)
    /// Persist the wire-form turns produced by this exchange.
    func recordTurns(_ turns: [AgentTurn])
}
