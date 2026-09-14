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
}

// MARK: - Store

/// Local-first analytics: events and samples land in Application Support, can be exported
/// from Settings, and are uploaded when an endpoint is configured.
final class Analytics {
    static let shared = Analytics()

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

    /// Random per-install id; not tied to the person or the device.
    static var installId: String {
        let key = "analytics.installId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static var context: [String: JSONValue] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return [
            "app": .string("\(version) (\(build))"),
            "os": .string(UIDevice.current.systemVersion),
            "device": .string(UIDevice.current.model),
            "locale": .string(Locale.current.identifier),
        ]
    }

    // MARK: Recording

    func track(_ name: String, _ properties: [String: JSONValue] = [:]) {
        guard AnalyticsConsent.usage else { return }
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
        let sample = RecognitionSample(
            id: UUID(), timestamp: Date(), model: model,
            recognized: recognized, corrected: corrected, accepted: accepted,
            imageWidth: Int(size.width), imageHeight: Int(size.height),
            imageBase64: jpeg?.base64EncodedString()
        )
        queue.async {
            guard let data = try? Analytics.encoder.encode(sample) else { return }
            try? data.write(to: self.samplesURL.appendingPathComponent("\(sample.id.uuidString).json"), options: .atomic)
        }
        track(corrected == nil ? "scan_accepted" : "scan_corrected", ["model": .string(model), "components": .init(recognized.components.count)])
    }

    // MARK: Inspection, export, deletion

    struct Summary {
        var events: Int
        var samples: Int
        var bytes: Int64
    }

    func summary() -> Summary {
        queue.sync {
            let eventCount = (try? String(contentsOf: eventsURL, encoding: .utf8))?.split(separator: "\n").count ?? 0
            let files = (try? FileManager.default.contentsOfDirectory(at: samplesURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            var bytes: Int64 = (try? FileManager.default.attributesOfItem(atPath: eventsURL.path)[.size] as? Int64) ?? 0
            for file in files { bytes += (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0 }
            return Summary(events: eventCount, samples: files.count, bytes: bytes)
        }
    }

    /// One JSON file with everything, for sharing by AirDrop / Files / Mail.
    func exportFile() -> URL? {
        queue.sync {
            let events = (try? String(contentsOf: eventsURL, encoding: .utf8))?.split(separator: "\n").compactMap { try? JSONDecoder.analytics.decode(AnalyticsEvent.self, from: Data($0.utf8)) } ?? []
            let samples = ((try? FileManager.default.contentsOfDirectory(at: samplesURL, includingPropertiesForKeys: nil)) ?? []).compactMap { url -> RecognitionSample? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.analytics.decode(RecognitionSample.self, from: data)
            }
            let payload = UploadPayload(installId: Analytics.installId, exportedAt: Date(), events: events, samples: samples)
            guard let data = try? Analytics.encoder.encode(payload) else { return nil }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("photomesh-data-\(stamp).json")
            try? data.write(to: url, options: .atomic)
            return url
        }
    }

    func deleteAll() {
        queue.async {
            try? FileManager.default.removeItem(at: self.eventsURL)
            try? FileManager.default.removeItem(at: self.samplesURL)
            try? FileManager.default.createDirectory(at: self.samplesURL, withIntermediateDirectories: true)
        }
    }

    // MARK: Upload

    struct UploadPayload: Codable {
        var installId: String
        var exportedAt: Date
        var events: [AnalyticsEvent]
        var samples: [RecognitionSample]
    }

    static var endpoint: URL? {
        guard let text = UserDefaults.standard.string(forKey: "analytics.endpoint"), let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }

    static var endpointKey: String {
        UserDefaults.standard.string(forKey: "analytics.endpointKey") ?? ""
    }

    private var isUploading = false

    /// Sends everything pending to the configured endpoint and clears it on success. Silent otherwise.
    func flush() {
        guard let endpoint = Analytics.endpoint else { return }
        queue.async {
            guard !self.isUploading else { return }
            let events = (try? String(contentsOf: self.eventsURL, encoding: .utf8))?.split(separator: "\n").compactMap { try? JSONDecoder.analytics.decode(AnalyticsEvent.self, from: Data($0.utf8)) } ?? []
            let sampleFiles = (try? FileManager.default.contentsOfDirectory(at: self.samplesURL, includingPropertiesForKeys: nil)) ?? []
            let samples = sampleFiles.compactMap { url -> RecognitionSample? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.analytics.decode(RecognitionSample.self, from: data)
            }
            guard !events.isEmpty || !samples.isEmpty else { return }
            let payload = UploadPayload(installId: Analytics.installId, exportedAt: Date(), events: events, samples: samples)
            guard let body = try? Analytics.encoder.encode(payload) else { return }
            self.isUploading = true

            var request = URLRequest(url: endpoint, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Analytics.endpointKey, forHTTPHeaderField: "X-PhotoMesh-Key")
            request.httpBody = body
            let task = URLSession.shared.dataTask(with: request) { _, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.queue.async {
                    self.isUploading = false
                    guard (200...299).contains(status) else {
                        RecognitionLog.shared.record("analytics upload failed (HTTP \(status))")
                        return
                    }
                    try? FileManager.default.removeItem(at: self.eventsURL)
                    for file in sampleFiles { try? FileManager.default.removeItem(at: file) }
                    RecognitionLog.shared.record("analytics uploaded: \(events.count) events, \(samples.count) samples")
                }
            }
            task.resume()
        }
    }

    // MARK: Helpers

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
