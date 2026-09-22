import Foundation

/// The one guardrail on free scanning: a soft cap per calendar month that almost nobody reaches.
/// It protects the shared key against abuse and never sells anything: the message says when the
/// scans come back, not what to buy. Bonus scans (`ScanCredits`) cover a full month. Personal keys
/// entered by a developer are not metered.
final class UsageAllowance {
    static let shared = UsageAllowance()

    /// Free devices.
    static let monthlyLimit = 30
    /// Subscribers: high enough never to be met in honest use, low enough to stop a script.
    static let plusMonthlyLimit = 300

    private let defaultsKey = "usage.recognitionCalls"

    struct Status {
        var usedThisMonth: Int
        var limit: Int
        var resetsAt: Date
        /// Bonus scans that would be spent once the month is full.
        var bonus: Int
        var remaining: Int { max(0, limit - usedThisMonth) }
        var isFull: Bool { usedThisMonth >= limit }
        var isBlocked: Bool { isFull && bonus == 0 }
    }

    enum LimitError: LocalizedError {
        case monthly(limit: Int, until: Date)

        var errorDescription: String? {
            switch self {
            case .monthly(let limit, let until):
                return "You've used this month's \(limit) scans. They come back on \(UsageAllowance.dayText(until)). Circuits you draw by hand still solve."
            }
        }
    }

    func status(plus: Bool) -> Status {
        let now = Date()
        return Status(usedThisMonth: callsThisMonth(now: now).count, limit: plus ? Self.plusMonthlyLimit : Self.monthlyLimit,
                      resetsAt: Self.nextMonth(after: now), bonus: ScanCredits.balance)
    }

    /// Records one scan, or throws when the month is full and no bonus scan can cover it.
    /// A bonus scan is not counted against the month.
    func consume(plus: Bool) throws {
        let now = Date()
        let calls = callsThisMonth(now: now)
        let limit = plus ? Self.plusMonthlyLimit : Self.monthlyLimit
        if calls.count >= limit {
            if ScanCredits.spend() {
                RecognitionLog.shared.record("month's scans used: spent a bonus scan, \(ScanCredits.balance) left")
                return
            }
            throw LimitError.monthly(limit: limit, until: Self.nextMonth(after: now))
        }
        save(calls + [now])
    }

    /// Developer options: start over.
    func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func callsThisMonth(now: Date) -> [Date] {
        let start = Self.monthStart(of: now)
        let stamps = UserDefaults.standard.array(forKey: defaultsKey) as? [Double] ?? []
        return stamps.map { Date(timeIntervalSince1970: $0) }
            .filter { $0 >= start && $0 <= now }
            .sorted()
    }

    private func save(_ calls: [Date]) {
        UserDefaults.standard.set(calls.map(\.timeIntervalSince1970), forKey: defaultsKey)
    }

    static func monthStart(of date: Date) -> Date {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: parts) ?? date
    }

    static func nextMonth(after date: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: 1, to: monthStart(of: date)) ?? date
    }

    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
