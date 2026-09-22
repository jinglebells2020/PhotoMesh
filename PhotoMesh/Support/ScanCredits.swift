import Foundation

/// Bonus scans earned by helping: turning scan sharing on, fixing a misread circuit, rating a
/// walkthrough, answering the questionnaire. A bonus scan is spent only when the beta allowance
/// window is full, so it never costs a subscriber anything and never goes to waste on a free
/// day. Everything lives in UserDefaults; the balance is capped so credits cannot pile up.
enum ScanCredits {
    enum Reason: String, CaseIterable, Codable {
        /// Scan sharing switched on for the first time.
        case sharing
        /// A walkthrough rated with a thumb (and reasons when it did not help).
        case feedback
        /// A misread scan corrected with "Fix something" while sharing is on.
        case correction
        /// The five-question survey answered.
        case survey

        var reward: Int {
            switch self {
            case .sharing: return 10
            case .feedback: return 2
            case .correction: return 2
            case .survey: return 5
            }
        }

        /// How many times a day this kind pays out; nil means once ever.
        var dailyCap: Int? {
            switch self {
            case .sharing, .survey: return nil
            case .feedback: return 3
            case .correction: return 5
            }
        }

        var title: String {
            switch self {
            case .sharing: return "Share your scans"
            case .feedback: return "Rate a walkthrough"
            case .correction: return "Fix a misread circuit"
            case .survey: return "Answer five questions"
            }
        }

        var detail: String {
            switch self {
            case .sharing: return "Your circuit pictures with the recognized and corrected netlists train the reader. Once, when you turn it on."
            case .feedback: return "After any solution, tap thumbs up or down under the steps. When it did not help, tell us why."
            case .correction: return "When a scan comes out wrong, tap Fix something and correct it. Needs scan sharing, because the fix is the lesson."
            case .survey: return "Who you are and what you need from the app. Two minutes, once."
            }
        }

        var systemImage: String {
            switch self {
            case .sharing: return "square.and.arrow.up.on.square"
            case .feedback: return "hand.thumbsup"
            case .correction: return "wrench.and.screwdriver"
            case .survey: return "list.bullet.clipboard"
            }
        }
    }

    /// The most that can be banked.
    static let bankLimit = 60

    static let didChange = Notification.Name("ScanCredits.didChange")

    private static let balanceKey = "credits.balance"
    private static let earnedKey = "credits.earned"
    private static let spentKey = "credits.spent"
    private static let awardsKey = "credits.awards"      // reason → timestamps
    private static let onceKey = "credits.once"          // reasons paid once

    private static var defaults: UserDefaults { .standard }

    static var balance: Int { max(0, defaults.integer(forKey: balanceKey)) }
    static var earnedTotal: Int { defaults.integer(forKey: earnedKey) }
    static var spentTotal: Int { defaults.integer(forKey: spentKey) }

    /// Whether `reason` would pay out right now.
    static func canAward(_ reason: Reason) -> Bool {
        if reason.dailyCap == nil { return !oncePaid.contains(reason.rawValue) }
        return awardsToday(reason) < (reason.dailyCap ?? 0)
    }

    /// Rewards of this kind paid out today.
    static func awardsToday(_ reason: Reason) -> Int {
        let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return (awards[reason.rawValue] ?? []).filter { $0 >= start }.count
    }

    /// Rewards of this kind paid out ever.
    static func awardsTotal(_ reason: Reason) -> Int {
        if reason.dailyCap == nil { return oncePaid.contains(reason.rawValue) ? 1 : 0 }
        return (awards[reason.rawValue] ?? []).count
    }

    /// Pays the reward for `reason` if its cap allows. Returns the credits actually granted.
    @discardableResult
    static func award(_ reason: Reason) -> Int {
        guard canAward(reason) else { return 0 }
        let granted = min(reason.reward, max(0, bankLimit - balance))
        if reason.dailyCap == nil {
            var paid = oncePaid
            paid.insert(reason.rawValue)
            defaults.set(Array(paid), forKey: onceKey)
        } else {
            var all = awards
            all[reason.rawValue, default: []].append(Date().timeIntervalSince1970)
            // Keep the ledger short: only the last two days matter.
            let cutoff = Date().timeIntervalSince1970 - 2 * 86400
            all[reason.rawValue] = all[reason.rawValue]?.filter { $0 >= cutoff }
            defaults.set(all, forKey: awardsKey)
        }
        defaults.set(balance + granted, forKey: balanceKey)
        defaults.set(earnedTotal + granted, forKey: earnedKey)
        Analytics.shared.track("credits_earned", ["reason": .string(reason.rawValue), "credits": .init(granted), "balance": .init(balance)])
        NotificationCenter.default.post(name: didChange, object: nil)
        return granted
    }

    /// Spends one bonus scan. False when there is none.
    static func spend() -> Bool {
        guard balance > 0 else { return false }
        defaults.set(balance - 1, forKey: balanceKey)
        defaults.set(spentTotal + 1, forKey: spentKey)
        Analytics.shared.track("credits_spent", ["balance": .init(balance)])
        NotificationCenter.default.post(name: didChange, object: nil)
        return true
    }

    /// Developer options: start over.
    static func reset() {
        for key in [balanceKey, earnedKey, spentKey, awardsKey, onceKey] { defaults.removeObject(forKey: key) }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static var awards: [String: [Double]] {
        defaults.dictionary(forKey: awardsKey) as? [String: [Double]] ?? [:]
    }

    private static var oncePaid: Set<String> {
        Set(defaults.stringArray(forKey: onceKey) ?? [])
    }
}
