import Foundation

/// A calendar day, independent of time zone drift within a session.
///
/// Using a `Date` as a day key is a classic source of off-by-one bugs (DST, the
/// user crossing midnight mid-conversation). `DayID` is the key everywhere; `Date`
/// only appears on individual entries where the actual clock time matters.
struct DayID: Codable, Hashable, Sendable, Comparable, Identifiable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    var id: String { description }

    /// ISO-ish, sortable, and safe as a file name: "2026-09-01".
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    static var today: DayID { DayID(.now) }

    /// Noon local time — a safe representative instant that survives DST transitions.
    func date(calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        return calendar.date(from: c) ?? .now
    }

    func advanced(by days: Int, calendar: Calendar = .current) -> DayID {
        guard let d = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) else {
            return self
        }
        return DayID(d, calendar: calendar)
    }

    /// Whole days from `self` to `other`. Negative when `other` is in the past.
    func distance(to other: DayID, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day ?? 0
    }

    static func < (lhs: DayID, rhs: DayID) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Display

    var isToday: Bool { self == .today }
    var isYesterday: Bool { self == DayID.today.advanced(by: -1) }
    var isFuture: Bool { self > .today }

    /// "Today" / "Yesterday" / "Monday" / "Mon, Aug 4" — whichever is shortest and
    /// still unambiguous at this distance from today.
    var title: String {
        if isToday { return "Today" }
        if isYesterday { return "Yesterday" }
        let delta = DayID.today.distance(to: self)
        let formatter = DateFormatter()
        if delta < 0 && delta > -7 {
            formatter.dateFormat = "EEEE"          // "Monday"
        } else if abs(delta) < 300 {
            formatter.dateFormat = "EEE, MMM d"    // "Mon, Aug 4"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date())
    }

    /// Always-explicit form for headers where "Today" would lose the date.
    var longTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date())
    }
}
