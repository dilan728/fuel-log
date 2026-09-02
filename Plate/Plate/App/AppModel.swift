import SwiftUI
import OSLog

/// The root of the app's state.
///
/// Owns the day the user is looking at, which surface is showing, and one
/// `ThreadSession` per day. The Catalog reads through the same sessions the Thread
/// does, so there is exactly one in-memory representation of a day and the two
/// surfaces can never disagree.
@MainActor
@Observable
final class AppModel {

    /// Which surface is showing. The pinch drives `zoom` continuously; `surface` is
    /// where it settles.
    enum Surface: Equatable {
        case thread
        case catalog
    }

    var surface: Surface = .thread
    /// 0 = fully Thread, 1 = fully Catalog. Driven directly by the pinch gesture, so
    /// the transition is scrubbable rather than a canned animation.
    var zoom: Double = 0

    var focusedDay: DayID = .today
    var profile = UserProfile()
    var presentedEntry: EntryReference?
    var isShowingSettings = false
    var isShowingOnboarding = false

    /// Days that have something logged, newest first. Backs the Catalog.
    private(set) var loggedDays: [DayID] = []
    /// The oldest day the pager will reach.
    private(set) var earliestDay: DayID = DayID.today.advanced(by: -30)

    /// Not observed. `session(for:)` is called from view bodies and lazily inserts
    /// here; if this dictionary participated in observation, that write would be a
    /// mutation during view evaluation — which SwiftUI responds to by dropping the
    /// update, and the thread renders blank.
    @ObservationIgnored private var sessions: [DayID: ThreadSession] = [:]
    @ObservationIgnored private let store: LogStore
    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let imageService: FoodImageService
    @ObservationIgnored private let logger = Logger(subsystem: "com.plate.Plate", category: "AppModel")

    /// Foods whose generation already failed. Retrying them on every scroll would burn
    /// the user's quota on something that is not going to start working.
    @ObservationIgnored private var abandonedImageKeys: Set<String> = []

    init(
        store: LogStore = .shared,
        profileStore: ProfileStore = .shared,
        imageService: FoodImageService = .shared
    ) {
        self.store = store
        self.profileStore = profileStore
        self.imageService = imageService
    }

    /// A reference to an entry that survives the day it lives on being reloaded.
    struct EntryReference: Identifiable, Equatable {
        var id: UUID
        var day: DayID
    }

    // MARK: Lifecycle

    func bootstrap() async {
        profile = await profileStore.profile()
        isShowingOnboarding = !profile.hasCompletedOnboarding
        loggedDays = await store.knownDays().asyncFilter { await !self.store.day($0).entries.isEmpty }

        if let oldest = loggedDays.last {
            earliestDay = min(oldest, DayID.today.advanced(by: -30))
        }

        await session(for: focusedDay).loadIfNeeded()

        #if DEBUG
        // Lets a debug build be launched straight onto a surface, for screenshotting
        // and for verifying the Catalog without having to perform the pinch.
        if ProcessInfo.processInfo.environment["PLATE_SURFACE"] == "catalog" {
            zoom = 1
            surface = .catalog
        }
        #endif
    }

    func saveProfile(_ mutate: @escaping (inout UserProfile) -> Void) async {
        profile = await profileStore.update(mutate)
    }

    func flush() async {
        await store.flush()
    }

    // MARK: Sessions

    func session(for day: DayID) -> ThreadSession {
        if let existing = sessions[day] { return existing }
        let created = ThreadSession(day: day, store: store, profileStore: profileStore)
        created.onEntriesLogged = { [weak self, weak created] ids in
            guard let self, let created else { return }
            Task { await self.generateImages(for: ids, in: created) }
        }
        sessions[day] = created
        return created
    }

    /// Pages the Thread and the Catalog together, so pinching out lands on the day you
    /// were reading rather than at the top of the list.
    func focus(_ day: DayID) {
        guard day != focusedDay else { return }
        focusedDay = day
        Task {
            await session(for: day).loadIfNeeded()
            await refreshLoggedDays()
        }
    }

    var canGoBack: Bool { focusedDay > earliestDay }
    var canGoForward: Bool { focusedDay < .today }

    // MARK: Imagery

    /// Kicks off photography for freshly logged entries.
    private func generateImages(for ids: [UUID], in session: ThreadSession) async {
        await refreshLoggedDays()
        for id in ids {
            guard let entry = session.entry(id) else { continue }
            await generateImage(for: entry, in: session)
        }
    }

    /// Requests an image if the entry doesn't have one. Safe to call repeatedly — the
    /// service de-duplicates by food, and abandoned foods are not retried.
    func ensureImage(for entry: FoodEntry, on day: DayID) {
        guard case .none = entry.image else { return }
        guard !abandonedImageKeys.contains(ImageCache.key(forFood: entry.name)) else { return }
        let session = session(for: day)
        Task { await generateImage(for: entry, in: session) }
    }

    private func generateImage(for entry: FoodEntry, in session: ThreadSession) async {
        let key = ImageCache.key(forFood: entry.name)
        guard !abandonedImageKeys.contains(key) else { return }

        // Already photographed under a previous entry for the same food — adopt it
        // without a request. This is why the cache is keyed by food, not by entry.
        if ImageCache.shared.hasImage(for: key) {
            await session.updateEntry(entry.id) { $0.image = .ready(fileName: key) }
            return
        }

        guard imageService.isConfigured else { return }

        await session.updateEntry(entry.id) { $0.image = .generating }

        do {
            let fileName = try await imageService.image(for: entry)
            await session.updateEntry(entry.id) { $0.image = .ready(fileName: fileName) }
            Haptics.shared.materialize()
        } catch {
            logger.error("Imagery failed for \(entry.name, privacy: .public): \(error.localizedDescription)")
            abandonedImageKeys.insert(key)
            await session.updateEntry(entry.id) {
                $0.image = .failed(reason: error.localizedDescription)
            }
        }
    }

    /// Re-runs photography for anything still without a picture — used after a key is
    /// added in Settings, so the existing log fills in rather than staying half-drawn.
    func backfillImages() async {
        abandonedImageKeys.removeAll()
        for day in loggedDays.prefix(60) {
            let session = session(for: day)
            await session.loadIfNeeded()
            for entry in session.entries {
                if case .ready = entry.image { continue }
                await session.updateEntry(entry.id) { $0.image = .none }
                await generateImage(for: entry, in: session)
            }
        }
    }

    // MARK: Days

    func refreshLoggedDays() async {
        var days: [DayID] = []
        for day in await store.knownDays() where await !store.day(day).entries.isEmpty {
            days.append(day)
        }
        loggedDays = days
        if let oldest = days.last {
            earliestDay = min(oldest, DayID.today.advanced(by: -30))
        }
    }
}

// MARK: - Helpers

private extension Array {
    /// `filter` with an async predicate. Sequential on purpose — the predicate reads
    /// through an actor, and fanning out would just queue up on the same actor anyway.
    func asyncFilter(_ isIncluded: (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self where await isIncluded(element) {
            result.append(element)
        }
        return result
    }
}
