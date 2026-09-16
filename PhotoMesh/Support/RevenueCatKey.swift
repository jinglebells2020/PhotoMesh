import Foundation

/// RevenueCat *public* SDK key. Unlike the OpenRouter key, this one is meant to ship inside the
/// app: it can only read offerings and make purchases for this app, never touch the dashboard.
///
/// `test_…` keys talk to RevenueCat's sandbox. Swap in the production key (`appl_…`) from
/// RevenueCat → Project settings → API keys before the App Store release.
enum RevenueCatKey {
    static let `public` = "test_vaVLwtAwmNDITQzxCllTFoCqwee"
}
