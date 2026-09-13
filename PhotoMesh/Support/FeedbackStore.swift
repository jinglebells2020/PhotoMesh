import Foundation
import UIKit

/// What a user told us after a walkthrough. Kept on the device; exportable from Diagnostics.
struct FeedbackEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var helpful: Bool
    var reasons: [String]
    var comment: String
    var question: String
    var method: String
}

enum FeedbackStore {
    static let reasons = ["Wrong answer", "A step is wrong", "Explanation is confusing", "Circuit was misread", "Too many steps", "Something else"]
    static let supportEmail = "hello@photomesh.app"
    /// Fill in once the app exists in App Store Connect (numeric id) to open the review page directly.
    static let appStoreID: String? = nil

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PhotoMesh", isDirectory: true).appendingPathComponent("feedback.json")
    }

    static func all() -> [FeedbackEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FeedbackEntry].self, from: data)) ?? []
    }

    static func save(_ entry: FeedbackEntry) {
        var entries = all()
        entries.insert(entry, at: 0)
        if entries.count > 300 { entries.removeLast(entries.count - 300) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        RecognitionLog.shared.record("feedback: \(entry.helpful ? "helpful" : "not helpful") \(entry.reasons.joined(separator: ", ")) \(entry.comment)")
    }

    /// Opens Mail with the feedback pre-filled (no backend yet).
    static func mailURL(for entry: FeedbackEntry) -> URL? {
        let subject = "PhotoMesh feedback"
        let body = """
        Helpful: \(entry.helpful ? "yes" : "no")
        Question: \(entry.question)
        Method: \(entry.method)
        Reasons: \(entry.reasons.joined(separator: ", "))
        Comment: \(entry.comment)

        Diagnostics:
        \(RecognitionLog.shared.text.split(separator: "\n").suffix(12).joined(separator: "\n"))
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url
    }

    /// Direct "write a review" page when the App Store id is known.
    static var writeReviewURL: URL? {
        guard let appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    // MARK: Rating prompt bookkeeping

    private static let ratedKey = "feedback.rated"
    private static let declinedKey = "feedback.declinedCount"

    /// Whether to ask for a rating after a positive answer (never after rating, at most twice declined).
    static var shouldAskForRating: Bool {
        !UserDefaults.standard.bool(forKey: ratedKey) && UserDefaults.standard.integer(forKey: declinedKey) < 2
    }

    static func markRated() { UserDefaults.standard.set(true, forKey: ratedKey) }
    static func markDeclined() { UserDefaults.standard.set(UserDefaults.standard.integer(forKey: declinedKey) + 1, forKey: declinedKey) }
}
