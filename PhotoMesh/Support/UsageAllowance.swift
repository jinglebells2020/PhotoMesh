import Foundation

/// Per-device caps on recognition calls made with the built-in tester key, so one enthusiastic
/// tester cannot drain the shared credit. Rolling windows: calls in the last hour and the last day.
/// Personal keys (entered by a developer) are not metered.
final class UsageAllowance {
    static let shared = UsageAllowance()

    static let hourlyLimit = 12
    static let dailyLimit = 40

    private let defaultsKey = "usage.recognitionCalls"
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    struct Status {
        var usedThisHour: Int
        var usedToday: Int
        var remainingToday: Int
        /// When the next call becomes possible, if a limit is currently reached.
        var blockedUntil: Date?
        var isBlocked: Bool { blockedUntil != nil }
    }

    enum LimitError: LocalizedError {
        case hourly(until: Date)
        case daily(until: Date)

        var errorDescription: String? {
            switch self {
            case .hourly(let until):
                return "Beta limit: \(UsageAllowance.hourlyLimit) scans per hour on the shared key. You can scan again at \(UsageAllowance.timeText(until))."
            case .daily(let until):
                return "Beta limit: \(UsageAllowance.dailyLimit) scans per day on the shared key. You can scan again at \(UsageAllowance.timeText(until))."
            }
        }
    }

    var status: Status {
        let now = Date()
        let calls = recentCalls(now: now)
        let lastHour = calls.filter { now.timeIntervalSince($0) < hour }
        var blockedUntil: Date?
        if calls.count >= Self.dailyLimit, let oldest = calls.first {
            blockedUntil = oldest.addingTimeInterval(day)
        } else if lastHour.count >= Self.hourlyLimit, let oldest = lastHour.first {
            blockedUntil = oldest.addingTimeInterval(hour)
        }
        return Status(usedThisHour: lastHour.count, usedToday: calls.count, remainingToday: max(0, Self.dailyLimit - calls.count), blockedUntil: blockedUntil)
    }

    /// Records one call, or throws when a window is full.
    func consume() throws {
        let now = Date()
        let calls = recentCalls(now: now)
        if calls.count >= Self.dailyLimit, let oldest = calls.first {
            throw LimitError.daily(until: oldest.addingTimeInterval(day))
        }
        let lastHour = calls.filter { now.timeIntervalSince($0) < hour }
        if lastHour.count >= Self.hourlyLimit, let oldest = lastHour.first {
            throw LimitError.hourly(until: oldest.addingTimeInterval(hour))
        }
        save(calls + [now])
    }

    /// Records one call if there is room; false (and nothing recorded) otherwise.
    func tryConsume() -> Bool {
        do { try consume(); return true } catch { return false }
    }

    /// Developer options: start over.
    func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func recentCalls(now: Date) -> [Date] {
        let stamps = UserDefaults.standard.array(forKey: defaultsKey) as? [Double] ?? []
        return stamps.map { Date(timeIntervalSince1970: $0) }
            .filter { now.timeIntervalSince($0) < day && $0 <= now }
            .sorted()
    }

    private func save(_ calls: [Date]) {
        UserDefaults.standard.set(calls.map(\.timeIntervalSince1970), forKey: defaultsKey)
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
