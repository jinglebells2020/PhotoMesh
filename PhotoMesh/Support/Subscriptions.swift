import Foundation
import Observation
import RevenueCat

/// Everything the app needs to know about the user's subscription, in one place.
///
/// `configure()` runs once at launch; after that the app reads `isPro` and, where it matters,
/// `store.status`. Entitlement state is kept live by RevenueCat's `customerInfoStream`, so a
/// purchase made on the paywall, a restore, a refund or an expiry all land here without extra work.
@MainActor
@Observable
final class Subscriptions {
    static let shared = Subscriptions()

    /// Entitlement configured in the RevenueCat dashboard; grants everything paid.
    static let entitlement = "photocircuits_pro"

    enum Status: Equatable {
        case unknown            // before the first customer info arrives
        case free
        case pro(expires: Date?, willRenew: Bool)
    }

    private(set) var status: Status = .unknown
    private(set) var offerings: Offerings?
    /// Last purchase/restore failure worth showing; the paywall handles its own errors.
    private(set) var lastError: String?
    /// Why there is nothing to sell. Empty offerings are nearly always a dashboard or
    /// App Store Connect configuration problem rather than a device issue, so say so.
    private(set) var offeringProblem: String?

    /// Packages in the current offering, in the order the dashboard lists them.
    var availablePackages: [Package] {
        offerings?.current?.availablePackages ?? []
    }

    var isPro: Bool {
        if case .pro = status { return true }
        return false
    }

    private var streamTask: Task<Void, Never>?

    private init() {}

    // MARK: Lifecycle

    /// Call once, as early as possible, before any other RevenueCat use.
    static func configure(apiKey: String) {
        #if DEBUG
        Purchases.logLevel = .info
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
        shared.start()
    }

    /// Applies the customer info RevenueCat already has, then follows every later change.
    private func start() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
        Task { await refresh() }
    }

    /// Pulls customer info and offerings. Safe to call on appear; RevenueCat caches both.
    func refresh() async {
        do {
            apply(try await Purchases.shared.customerInfo())
        } catch {
            // Offline or a transient backend problem: keep the cached entitlement state.
            lastError = error.localizedDescription
        }
        do {
            let fetched = try await Purchases.shared.offerings()
            offerings = fetched
            if fetched.current == nil {
                offeringProblem = "No current offering. Set one as current in RevenueCat → Offerings."
            } else if fetched.current?.availablePackages.isEmpty ?? true {
                offeringProblem = "The current offering has no packages, or its products are not ready in App Store Connect."
            } else {
                offeringProblem = nil
            }
        } catch {
            offerings = nil
            offeringProblem = error.localizedDescription
        }
    }

    private func apply(_ info: CustomerInfo) {
        if let pro = info.entitlements[Self.entitlement], pro.isActive {
            status = .pro(expires: pro.expirationDate, willRenew: pro.willRenew)
        } else {
            status = .free
        }
        UserDefaults.standard.set(isPro, forKey: Self.cacheKey)
    }

    // MARK: Synchronous access

    nonisolated private static let cacheKey = "subscription.isPro"

    /// Last known entitlement state, readable from any actor (the solver runs off the main one).
    /// Mirrors `isPro` and survives launches, so a subscriber is never briefly rate-limited while
    /// RevenueCat is still fetching.
    nonisolated static var isProCached: Bool {
        UserDefaults.standard.bool(forKey: cacheKey)
    }

    // MARK: Purchases

    /// Buys a package. Returns true when the entitlement is active afterwards.
    /// A cancelled purchase is not an error and returns false without setting `lastError`.
    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        lastError = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return false }
            apply(result.customerInfo)
            return isPro
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    /// Restores purchases made with this Apple Account. Returns true when the entitlement is back.
    @discardableResult
    func restore() async -> Bool {
        lastError = nil
        do {
            apply(try await Purchases.shared.restorePurchases())
            if !isPro { lastError = "No active subscription was found for this Apple Account." }
            return isPro
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    func clearError() { lastError = nil }

    /// RevenueCat wraps StoreKit failures in `ErrorCode`; these are the ones worth wording ourselves.
    private static func message(for error: Error) -> String? {
        guard let code = error as? ErrorCode else { return error.localizedDescription }
        switch code {
        case .purchaseCancelledError: return nil
        case .networkError, .offlineConnectionError:
            return "No connection. Check your network and try again."
        case .purchaseNotAllowedError:
            return "Purchases are not allowed on this device (check Screen Time restrictions)."
        case .paymentPendingError:
            return "The purchase is pending approval. Access unlocks once it goes through."
        case .productNotAvailableForPurchaseError, .productAlreadyPurchasedError:
            return "That plan is not available right now."
        case .storeProblemError:
            return "The App Store is having trouble. Please try again in a moment."
        default:
            return code.localizedDescription
        }
    }
}

extension Subscriptions.Status {
    /// Short line for Settings, e.g. "Renews 3 Oct 2026".
    var detail: String {
        switch self {
        case .unknown: return ""
        case .free: return "Not subscribed"
        case .pro(let expires, let willRenew):
            guard let expires else { return "Active" }
            let date = expires.formatted(date: .abbreviated, time: .omitted)
            return willRenew ? "Renews \(date)" : "Ends \(date)"
        }
    }
}
