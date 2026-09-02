import Foundation
import OSLog

/// The source of truth for everything logged.
///
/// An actor, because three things mutate a day concurrently — the user editing, the
/// agent's tools writing, and image generation completing out of band — and the last
/// of those can land minutes after the conversation moved on.
///
/// One JSON file per day. Days are independent, so a corrupt file costs one day rather
/// than the whole history, and the working set stays small no matter how long someone
/// has used the app.
actor LogStore {
    static let shared = LogStore()

    private let logger = Logger(subsystem: "com.plate.Plate", category: "LogStore")
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Days currently in memory. Everything read goes through here.
    private var cache: [DayID: DayLog] = [:]
    private var dirty: Set<DayID> = []
    private var flushTask: Task<Void, Never>?

    /// All days that have a file on disk, newest first. Built once, maintained in place.
    private var knownDaysCache: [DayID]?

    init(root: URL? = nil) {
        let base = root ?? URL.applicationSupportDirectory.appending(path: "Plate/days")
        self.root = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Reading

    func day(_ id: DayID) -> DayLog {
        if let cached = cache[id] { return cached }
        let loaded = readFromDisk(id) ?? DayLog(id: id)
        cache[id] = loaded
        return loaded
    }

    /// Every day with something in it, newest first.
    func knownDays() -> [DayID] {
        if let knownDaysCache { return knownDaysCache }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path())) ?? []
        let days = names
            .filter { $0.hasSuffix(".json") }
            .compactMap { Self.parseDayID(fileName: $0) }
            .sorted(by: >)
        knownDaysCache = days
        return days
    }

    /// The most recent day that actually has food in it. Used to decide where to open.
    func mostRecentLoggedDay() -> DayID? {
        knownDays().first { !day($0).entries.isEmpty }
    }

    // MARK: Writing

    @discardableResult
    func update(_ id: DayID, _ mutate: (inout DayLog) -> Void) -> DayLog {
        var log = day(id)
        mutate(&log)
        log.updatedAt = .now
        cache[id] = log
        markDirty(id)
        return log
    }

    /// Convenience for the common single-entry mutations the tools perform.
    @discardableResult
    func updateEntry(_ entryID: UUID, on dayID: DayID, _ mutate: (inout FoodEntry) -> Void) -> FoodEntry? {
        var updated: FoodEntry?
        update(dayID) { log in
            guard let index = log.entries.firstIndex(where: { $0.id == entryID }) else { return }
            mutate(&log.entries[index])
            updated = log.entries[index]
        }
        return updated
    }

    /// Finds an entry anywhere in recent history. Image generation completes without
    /// knowing which day its entry ended up on (the agent can log to yesterday).
    func locateEntry(_ entryID: UUID, searchingBack days: Int = 14) -> DayID? {
        var candidate = DayID.today
        for _ in 0...days {
            if day(candidate).entry(entryID) != nil { return candidate }
            candidate = candidate.advanced(by: -1)
        }
        return knownDays().first { day($0).entry(entryID) != nil }
    }

    // MARK: History search
    //
    // Backs the agent's `search_history` tool and the "log it again" flow.

    /// Entries whose name matches `query`, most recent first, de-duplicated by name so
    /// the agent sees six different foods rather than the same oatmeal six times.
    func searchHistory(query: String, limit: Int = 8, searchingBack days: Int = 120) -> [(entry: FoodEntry, day: DayID)] {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var results: [(FoodEntry, DayID)] = []
        var seenNames = Set<String>()

        for dayID in knownDays().prefix(days) {
            for entry in day(dayID).entriesInOrder.reversed() {
                let name = entry.name.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                )
                guard needle.isEmpty || name.contains(needle) || needle.contains(name) else { continue }
                guard seenNames.insert(name).inserted else { continue }
                results.append((entry, dayID))
                if results.count >= limit { return results }
            }
        }
        return results
    }

    /// Daily totals over a window, for "how has my week been".
    func dailyTotals(endingAt end: DayID, days: Int) -> [(day: DayID, totals: NutritionFacts, entryCount: Int)] {
        (0..<max(days, 1)).reversed().compactMap { offset in
            let id = end.advanced(by: -offset)
            let log = day(id)
            guard !log.entries.isEmpty else { return nil }
            return (id, log.totals, log.entries.count)
        }
    }

    // MARK: Flushing
    //
    // Writes are debounced: the agent can mutate a day several times inside one turn,
    // and there is no reason to hit the disk for each one.

    private func markDirty(_ id: DayID) {
        dirty.insert(id)
        if knownDaysCache?.contains(id) == false {
            knownDaysCache?.append(id)
            knownDaysCache?.sort(by: >)
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Writes every pending day. Called on debounce and on scene-phase changes.
    func flush() {
        let pending = dirty
        dirty.removeAll()
        for id in pending {
            guard let log = cache[id] else { continue }
            writeToDisk(log)
        }
    }

    // MARK: Disk

    private func url(for id: DayID) -> URL {
        root.appending(path: "\(id.description).json")
    }

    private func readFromDisk(_ id: DayID) -> DayLog? {
        let location = url(for: id)
        guard let data = try? Data(contentsOf: location) else { return nil }
        do {
            return try decoder.decode(DayLog.self, from: data)
        } catch {
            // A day that fails to decode is quarantined rather than deleted, so it can
            // be recovered later, and the app carries on with an empty day.
            logger.error("Could not decode \(id.description): \(error.localizedDescription)")
            try? FileManager.default.moveItem(
                at: location,
                to: location.appendingPathExtension("corrupt-\(Int(Date.now.timeIntervalSince1970))")
            )
            return nil
        }
    }

    private func writeToDisk(_ log: DayLog) {
        do {
            let data = try encoder.encode(log)
            try data.write(to: url(for: log.id), options: [.atomic])
        } catch {
            logger.error("Could not write \(log.id.description): \(error.localizedDescription)")
        }
    }

    private static func parseDayID(fileName: String) -> DayID? {
        let stem = fileName.replacingOccurrences(of: ".json", with: "")
        let parts = stem.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DayID(year: parts[0], month: parts[1], day: parts[2])
    }

    // MARK: Testing / previews

    /// Replaces the contents of a day outright. Only used by preview seeding.
    func replace(_ log: DayLog) {
        cache[log.id] = log
        markDirty(log.id)
    }
}
