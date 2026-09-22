import Foundation
import UIKit
import Observation

// MARK: - Consent

/// What the user allowed. Everything is off until they say yes.
enum AnalyticsConsent {
    private static let usageKey = "analytics.usage"
    private static let scansKey = "analytics.scans"
    private static let askedKey = "analytics.asked"

    /// Anonymous usage events (no images).
    static var usage: Bool {
        get { UserDefaults.standard.bool(forKey: usageKey) }
        set { UserDefaults.standard.set(newValue, forKey: usageKey) }
    }

    /// Scan pictures with their recognized / corrected netlists, to improve recognition.
    static var scans: Bool {
        get { UserDefaults.standard.bool(forKey: scansKey) }
        set { UserDefaults.standard.set(newValue, forKey: scansKey) }
    }

    static var asked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }
}

// MARK: - Events

/// JSON-friendly property value.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(_ value: String) { self = .string(value) }
    init(_ value: Int) { self = .number(Double(value)) }
    init(_ value: Double) { self = .number(value) }
    init(_ value: Bool) { self = .bool(value) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        }
    }
}

struct AnalyticsEvent: Codable {
    var id: UUID
    var timestamp: Date
    var name: String
    var properties: [String: JSONValue]
}

/// A labelled example: the picture, what the reader said, and (when corrected) what was right.
struct RecognitionSample: Codable {
    var id: UUID
    var timestamp: Date
    var model: String
    var recognized: Circuit
    var corrected: Circuit?
    var accepted: Bool
    var imageWidth: Int
    var imageHeight: Int
    /// JPEG, base64. Present only when scan sharing is on.
    var imageBase64: String?
    /// What the person changed, when `corrected` is present.
    var diff: CorrectionDiff?
}

// MARK: - Store

/// Local-first analytics: events and samples land in Application Support, can be exported from
/// Settings, and upload themselves in size-bounded batches to the collector baked into the build
/// (or one set in developer settings). Nothing leaves the device without consent, except what the
/// person explicitly sends (feedback, the survey).
final class Analytics {
    static let shared = Analytics()

    /// Each upload request stays under this much JSON; pictures are the bulk.
    static let batchBytes = 6 * 1024 * 1024

    private let queue = DispatchQueue(label: "app.photomesh.analytics", qos: .utility)
    private let root: URL
    private var eventsURL: URL { root.appendingPathComponent("events.jsonl") }
    private var samplesURL: URL { root.appendingPathComponent("samples", isDirectory: true) }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        root = base.appendingPathComponent("PhotoMesh", isDirectory: true).appendingPathComponent("analytics", isDirectory: true)
        try? FileManager.default.createDirectory(at: samplesURL, withIntermediateDirectories: true)
    }

    // MARK: Identity and context

    static let installKey = "analytics.installId"
    private static let firstOpenKey = "analytics.firstOpen"

    /// Random per-install id; not tied to the person or the device. Renewed by `forget()`.
    static var installId: String {
        if let existing = UserDefaults.standard.string(forKey: installKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installKey)
        return fresh
    }

    /// One id per foreground session, so events can be grouped into visits.
    private(set) static var sessionId = UUID().uuidString
    private static var activeSince: Date?

    /// Days since the app was first opened.
    static var installAgeDays: Int {
        let first = UserDefaults.standard.double(forKey: firstOpenKey)
        guard first > 0 else { return 0 }
        return Int(Date().timeIntervalSince1970 - first) / 86400
    }

    /// Call when the app comes to the foreground. True the very first time ever.
    func becameActive() -> Bool {
        Analytics.sessionId = UUID().uuidString
        Analytics.activeSince = Date()
        if UserDefaults.standard.object(forKey: Analytics.firstOpenKey) == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Analytics.firstOpenKey)
            return true
        }
        return false
    }

    /// Call when the app leaves the foreground: the seconds it was active, if known.
    func becameInactive() -> Int? {
        defer { Analytics.activeSince = nil }
        guard let since = Analytics.activeSince else { return nil }
        return Int(Date().timeIntervalSince(since))
    }

    static var context: [String: JSONValue] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return [
            "app": .string("\(version) (\(build))"),
            "os": .string(UIDevice.current.systemVersion),
            "device": .string(UIDevice.current.model),
            "locale": .string(Locale.current.identifier),
            "plus": .bool(PlusAccessCached.hasPlus),
            "install_days": .init(installAgeDays),
            "session": .string(sessionId),
            "shares_scans": .bool(AnalyticsConsent.scans),
        ]
    }

    // MARK: Recording

    /// An anonymous usage event; dropped unless usage sharing is on.
    func track(_ name: String, _ properties: [String: JSONValue] = [:]) {
        guard AnalyticsConsent.usage else { return }
        record(name, properties)
    }

    /// Something the person explicitly sent us (feedback, the survey): kept whatever the usage setting says.
    func submit(_ name: String, _ properties: [String: JSONValue] = [:]) {
        record(name, properties)
    }

    private func record(_ name: String, _ properties: [String: JSONValue]) {
        let event = AnalyticsEvent(id: UUID(), timestamp: Date(), name: name, properties: properties.merging(Analytics.context) { current, _ in current })
        queue.async {
            guard let data = try? Analytics.encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return }
            self.append(line + "\n", to: self.eventsURL)
        }
    }

    /// Stores a scan the user accepted or corrected. Requires scan sharing.
    func recordSample(image: UIImage?, model: String, recognized: Circuit, corrected: Circuit?, accepted: Bool) {
        guard AnalyticsConsent.scans else { return }
        let jpeg = image?.pmJPEGData(maxDimension: 1280, quality: 0.8)
        let size = image?.size ?? .zero
        let diff = corrected.map { CorrectionDiff.between(recognized, $0) }
        let sample = RecognitionSample(
            id: UUID(), timestamp: Date(), model: model,
            recognized: recognized, corrected: corrected, accepted: accepted,
            imageWidth: Int(size.width), imageHeight: Int(size.height),
            imageBase64: jpeg?.base64EncodedString(), diff: diff
        )
        queue.async {
            guard let data = try? Analytics.encoder.encode(sample) else { return }
            try? data.write(to: self.samplesURL.appendingPathComponent("\(sample.id.uuidString).json"), options: .atomic)
        }
        var properties: [String: JSONValue] = ["model": .string(model), "components": .init(recognized.components.count), "sample": .string(sample.id.uuidString)]
        if let diff { properties.merge(diff.properties) { current, _ in current } }
        track(corrected == nil ? "scan_accepted" : "scan_corrected", properties)
    }

    // MARK: Inspection, export, deletion

    struct Summary {
        var events: Int
        var samples: Int
        var bytes: Int64
        var uploadedEvents: Int
        var uploadedSamples: Int
        var lastUploadAt: Date?
        var endpointConfigured: Bool
    }

    func summary() -> Summary {
        queue.sync {
            let eventFiles = [eventsURL] + pendingEventFiles
            var eventCount = 0
            var bytes: Int64 = 0
            for file in eventFiles {
                eventCount += (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").count ?? 0
                bytes += (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            }
            let files = sampleFiles()
            for file in files { bytes += (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0 }
            return Summary(events: eventCount, samples: files.count, bytes: bytes,
                           uploadedEvents: Analytics.uploadedEvents, uploadedSamples: Analytics.uploadedSamples,
                           lastUploadAt: Analytics.lastUploadAt, endpointConfigured: Analytics.endpoint != nil)
        }
    }

    /// One JSON file with everything, for sharing by AirDrop / Files / Mail.
    func exportFile() -> URL? {
        queue.sync {
            let events = ([eventsURL] + pendingEventFiles).flatMap(readEvents)
            let samples = sampleFiles().compactMap(readSample)
            let payload = UploadPayload(installId: Analytics.installId, exportedAt: Date(), context: Analytics.context, events: events, samples: samples)
            guard let data = try? Analytics.encoder.encode(payload) else { return nil }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("photocircuits-data-\(stamp).json")
            try? data.write(to: url, options: .atomic)
            return url
        }
    }

    func deleteAll() {
        queue.async {
            for file in [self.eventsURL] + self.pendingEventFiles { try? FileManager.default.removeItem(at: file) }
            try? FileManager.default.removeItem(at: self.samplesURL)
            try? FileManager.default.createDirectory(at: self.samplesURL, withIntermediateDirectories: true)
        }
    }

    /// Deletes everything on the device, asks the collector to erase what it holds for this
    /// install, and starts a fresh install id so nothing new can be linked to the old data.
    func forget(completion: @escaping (Bool) -> Void) {
        let oldId = Analytics.installId
        deleteAll()
        UserDefaults.standard.set(UUID().uuidString, forKey: Analytics.installKey)
        Analytics.resetUploadCounters()
        guard let endpoint = Analytics.endpoint else {
            DispatchQueue.main.async { completion(true) }
            return
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("forget"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Analytics.endpointKey, forHTTPHeaderField: "X-PhotoMesh-Key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["installId": oldId])
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            RecognitionLog.shared.record("forget request: HTTP \(status)")
            DispatchQueue.main.async { completion((200...299).contains(status)) }
        }.resume()
    }

    // MARK: Upload

    struct UploadPayload: Codable {
        var schema: Int = 2
        var installId: String
        var exportedAt: Date
        var context: [String: JSONValue]
        var events: [AnalyticsEvent]
        var samples: [RecognitionSample]
    }

    /// A developer override wins; otherwise the collector baked into the build.
    static var endpoint: URL? {
        if let text = UserDefaults.standard.string(forKey: SettingsKeys.analyticsEndpoint), !text.isEmpty {
            guard let url = URL(string: text), url.scheme == "https" else { return nil }
            return url
        }
        return BuiltinKey.telemetry?.endpoint
    }

    static var endpointKey: String {
        if let key = UserDefaults.standard.string(forKey: SettingsKeys.analyticsEndpointKey), !key.isEmpty { return key }
        return BuiltinKey.telemetry?.key ?? ""
    }

    static var usesBuiltInEndpoint: Bool {
        (UserDefaults.standard.string(forKey: SettingsKeys.analyticsEndpoint) ?? "").isEmpty && BuiltinKey.telemetry != nil
    }

    private static let uploadedEventsKey = "analytics.uploaded.events"
    private static let uploadedSamplesKey = "analytics.uploaded.samples"
    private static let uploadedAtKey = "analytics.uploaded.at"

    static var uploadedEvents: Int { UserDefaults.standard.integer(forKey: uploadedEventsKey) }
    static var uploadedSamples: Int { UserDefaults.standard.integer(forKey: uploadedSamplesKey) }
    static var lastUploadAt: Date? {
        let stamp = UserDefaults.standard.double(forKey: uploadedAtKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private static func noteUploaded(events: Int, samples: Int) {
        UserDefaults.standard.set(uploadedEvents + events, forKey: uploadedEventsKey)
        UserDefaults.standard.set(uploadedSamples + samples, forKey: uploadedSamplesKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: uploadedAtKey)
    }

    private static func resetUploadCounters() {
        for key in [uploadedEventsKey, uploadedSamplesKey, uploadedAtKey] { UserDefaults.standard.removeObject(forKey: key) }
    }

    private struct Batch {
        var eventFiles: [URL]
        var events: [AnalyticsEvent]
        var sampleFiles: [URL]
        var samples: [RecognitionSample]
    }

    private var isUploading = false
    private var failures = 0
    private var retryAfter: Date?

    /// Sends everything pending in batches and clears each batch once the collector has it.
    /// Silent on failure; the next call retries after a growing pause.
    func flush() {
        guard let endpoint = Analytics.endpoint else { return }
        queue.async {
            guard !self.isUploading else { return }
            if let retryAfter = self.retryAfter, retryAfter > Date() { return }
            self.rotateEvents()
            let eventFiles = self.pendingEventFiles
            let events = eventFiles.flatMap(self.readEvents)
            let sampleFiles = self.sampleFiles()
            guard !events.isEmpty || !sampleFiles.isEmpty else { return }

            var batches: [Batch] = []
            var current = Batch(eventFiles: eventFiles, events: events, sampleFiles: [], samples: [])
            var bytes = events.count * 512
            for file in sampleFiles {
                guard let data = try? Data(contentsOf: file), let sample = try? JSONDecoder.analytics.decode(RecognitionSample.self, from: data) else {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                if bytes + data.count > Analytics.batchBytes, !(current.events.isEmpty && current.samples.isEmpty) {
                    batches.append(current)
                    current = Batch(eventFiles: [], events: [], sampleFiles: [], samples: [])
                    bytes = 0
                }
                current.sampleFiles.append(file)
                current.samples.append(sample)
                bytes += data.count
            }
            batches.append(current)
            self.isUploading = true
            self.upload(batches, at: 0, to: endpoint)
        }
    }

    /// Runs on `queue`. Sends one batch, then the next; stops at the first failure.
    private func upload(_ batches: [Batch], at index: Int, to endpoint: URL) {
        guard index < batches.count else {
            isUploading = false
            return
        }
        let batch = batches[index]
        let payload = UploadPayload(installId: Analytics.installId, exportedAt: Date(), context: Analytics.context, events: batch.events, samples: batch.samples)
        guard let body = try? Analytics.encoder.encode(payload) else {
            isUploading = false
            return
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Analytics.endpointKey, forHTTPHeaderField: "X-PhotoMesh-Key")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            self.queue.async {
                guard (200...299).contains(status) else {
                    self.failures += 1
                    let delay = min(3600.0, 60.0 * pow(2.0, Double(min(self.failures, 6))))
                    self.retryAfter = Date().addingTimeInterval(delay)
                    self.isUploading = false
                    let why = error.map { ": \($0.localizedDescription)" } ?? ""
                    RecognitionLog.shared.record("upload failed (HTTP \(status)\(why)); next try in \(Int(delay)) s")
                    return
                }
                self.failures = 0
                self.retryAfter = nil
                for file in batch.eventFiles + batch.sampleFiles { try? FileManager.default.removeItem(at: file) }
                Analytics.noteUploaded(events: batch.events.count, samples: batch.samples.count)
                RecognitionLog.shared.record("uploaded \(batch.events.count) events, \(batch.samples.count) samples")
                self.upload(batches, at: index + 1, to: endpoint)
            }
        }.resume()
    }

    // MARK: Files

    /// Event files waiting to be sent; new events keep going to `events.jsonl` meanwhile.
    private var pendingEventFiles: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "pending" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Moves the live event file aside so an upload never races a write.
    private func rotateEvents() {
        guard FileManager.default.fileExists(atPath: eventsURL.path) else { return }
        let stamp = String(format: "%.0f", Date().timeIntervalSince1970 * 1000)
        try? FileManager.default.moveItem(at: eventsURL, to: root.appendingPathComponent("events-\(stamp).pending"))
    }

    private func sampleFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: samplesURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readEvents(_ url: URL) -> [AnalyticsEvent] {
        (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").compactMap { try? JSONDecoder.analytics.decode(AnalyticsEvent.self, from: Data($0.utf8)) } ?? []
    }

    private func readSample(_ url: URL) -> RecognitionSample? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.analytics.decode(RecognitionSample.self, from: data)
    }

    private func append(_ text: String, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let analytics: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
