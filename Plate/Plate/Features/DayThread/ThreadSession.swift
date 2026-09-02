import SwiftUI
import OSLog

/// One day's conversation, live.
///
/// This is both the view state for a day and the `AgentSink` the backend drives, which
/// is deliberate: streaming text arrives dozens of times a second, and routing it
/// through an extra layer of publishing showed up as visible stutter. The backend
/// writes here, the view reads here.
///
/// Persistence is deferred to the end of a turn. Writing the log on every token would
/// mean a disk write per character.
@MainActor
@Observable
final class ThreadSession {
    let day: DayID

    private(set) var messages: [ChatMessage] = []
    private(set) var entries: [FoodEntry] = []
    private(set) var isResponding = false
    /// Set when a turn fails. Shown inline with a retry, then cleared.
    private(set) var failure: String?

    var draft: String = ""

    private let store: LogStore
    private let profileStore: ProfileStore
    private let database: NutritionDatabase
    private let logger = Logger(subsystem: "com.plate.Plate", category: "Thread")

    /// Called when entries are created, so imagery can be started by whoever owns that.
    var onEntriesLogged: (([UUID]) -> Void)?

    private var transcript: [AgentTurn] = []
    private var streamingMessageID: UUID?
    private var pendingTurns: [AgentTurn] = []
    private var runTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        day: DayID,
        store: LogStore = .shared,
        profileStore: ProfileStore = .shared,
        database: NutritionDatabase = .shared
    ) {
        self.day = day
        self.store = store
        self.profileStore = profileStore
        self.database = database
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        let log = await store.day(day)
        messages = log.messages
        entries = log.entriesInOrder
        transcript = log.transcript
    }

    /// Re-reads entries from the store. Called when imagery lands or another surface
    /// changed the day.
    func refreshEntries() async {
        entries = await store.day(day).entriesInOrder
    }

    var totals: NutritionFacts {
        entries.reduce(.zero) { $0 + $1.facts }
    }

    var isEmpty: Bool { entries.isEmpty && messages.isEmpty }

    func entry(_ id: UUID) -> FoodEntry? {
        entries.first { $0.id == id }
    }

    // MARK: Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        draft = ""
        failure = nil
        append(.user(trimmed))
        Haptics.shared.commit()

        runTask = Task { await run(trimmed) }
    }

    /// Re-sends the last user message after a failure.
    func retry() {
        guard let last = messages.last(where: { $0.role == .user })?.text else { return }
        // Drop the failed reply so the retry doesn't stack two bubbles.
        if messages.last?.role == .agent { messages.removeLast() }
        failure = nil
        runTask = Task { await run(last) }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        isResponding = false
        finalizeStreamingMessage()
    }

    private func run(_ text: String) async {
        isResponding = true
        defer { isResponding = false }

        let profile = await profileStore.profile()
        let context = AgentRunContext(
            day: day,
            profile: profile,
            transcript: transcript,
            runner: AgentToolRunner(
                day: day,
                store: store,
                database: database,
                profileStore: profileStore
            )
        )

        let backend: AgentBackend
        if let key = Credentials.value(for: .anthropic) {
            backend = RemoteAgentBackend(apiKey: key)
        } else {
            backend = LocalAgentBackend(database: database)
        }

        await backend.run(userText: text, context: context, sink: self)
        await persist()
    }

    // MARK: Local mutation
    //
    // Used by the detail sheet's direct edits, which bypass the agent entirely — a
    // slider should not require a conversation.

    func updateEntry(_ id: UUID, _ mutate: @escaping (inout FoodEntry) -> Void) async {
        await store.updateEntry(id, on: day, mutate)
        await refreshEntries()
    }

    func deleteEntry(_ id: UUID) async {
        await store.update(day) { log in
            log.entries.removeAll { $0.id == id }
            for index in log.messages.indices {
                log.messages[index].entryIDs.removeAll { $0 == id }
            }
        }
        messages = await store.day(day).messages
        await refreshEntries()
        Haptics.shared.select()
    }

    // MARK: Persistence

    private func persist() async {
        let snapshot = messages
        let turns = transcript
        await store.update(day) { log in
            log.messages = snapshot
            log.transcript = turns
        }
        entries = await store.day(day).entriesInOrder
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
    }

    private func mutateStreamingMessage(_ mutate: (inout ChatMessage) -> Void) {
        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id })
        else { return }
        mutate(&messages[index])
    }

    private func finalizeStreamingMessage() {
        mutateStreamingMessage { message in
            message.state = .complete
            for index in message.activity.indices { message.activity[index].isComplete = true }
        }
        streamingMessageID = nil
    }
}

// MARK: - AgentSink

extension ThreadSession: AgentSink {

    func beginReply() {
        let message = ChatMessage(role: .agent, state: .streaming)
        streamingMessageID = message.id
        append(message)
    }

    func appendText(_ text: String) {
        mutateStreamingMessage { $0.text += text }
    }

    func beginActivity(_ activity: Activity) -> UUID {
        mutateStreamingMessage { $0.activity.append(activity) }
        return activity.id
    }

    func refineActivity(_ id: UUID, to activity: Activity) {
        mutateStreamingMessage { message in
            guard let index = message.activity.firstIndex(where: { $0.id == id }) else { return }
            // Keep the original id so the chip animates its text rather than being
            // replaced — a chip that disappears and reappears reads as a glitch.
            message.activity[index].label = activity.label
            message.activity[index].completedLabel = activity.completedLabel
            message.activity[index].kind = activity.kind
        }
    }

    func completeActivity(_ id: UUID) {
        mutateStreamingMessage { message in
            guard let index = message.activity.firstIndex(where: { $0.id == id }) else { return }
            message.activity[index].isComplete = true
        }
    }

    func attachEntries(_ ids: [UUID]) {
        mutateStreamingMessage { $0.entryIDs.append(contentsOf: ids) }
        Haptics.shared.mealLanded()
        onEntriesLogged?(ids)
    }

    func logDidChange() {
        Task { await refreshEntries() }
    }

    func recordTurns(_ turns: [AgentTurn]) {
        transcript.append(contentsOf: turns)
    }

    func finishReply(error: Error?) {
        if let error {
            logger.error("Turn failed: \(error.localizedDescription)")
            failure = error.localizedDescription
            mutateStreamingMessage { message in
                message.state = .failed(reason: error.localizedDescription)
                // An empty failed bubble is just noise; the inline error says enough.
                if message.text.isEmpty && message.activity.isEmpty {
                    message.text = ""
                }
            }
            streamingMessageID = nil
            Haptics.shared.failure()
        } else {
            finalizeStreamingMessage()
        }
    }
}
