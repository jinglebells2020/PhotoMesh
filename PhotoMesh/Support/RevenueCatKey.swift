import Foundation

/// RevenueCat *public* SDK key. Unlike the OpenRouter key, this one is meant to ship inside the
/// app: it can only read offerings and make purchases for this app, never touch the dashboard.
///
/// This is the App Store configuration's key (RevenueCat → API keys → "Photocircuits (App Store)"),
/// so purchases go through the real App Store rather than RevenueCat's Test Store.
enum RevenueCatKey {
    static let `public` = "appl_bDizgwXUBfGJyyCGAbCAwIIWeLA"
}
