import Foundation

/// Secrets baked into tester builds so nobody has to enter them: the OpenRouter key and the
/// telemetry collector's address and ingest key.
///
/// Nothing here is ever committed: `tools/embed-key.sh` writes the values (XOR-obfuscated so they
/// do not sit in the binary as plain text) right before archiving, and the TestFlight workflow
/// does the same from the `OPENROUTER_TESTER_KEY`, `TELEMETRY_ENDPOINT` and `TELEMETRY_KEY`
/// secrets. In git every array stays empty, and a check in the workflow fails the build if one
/// is not. Obfuscation is not secrecy: anyone determined can recover the values from the app, so
/// give the OpenRouter key a credit limit and rotate both keys freely.
enum BuiltinKey {
    // BEGIN EMBEDDED KEY (managed by tools/embed-key.sh; keep empty in git)
    private static let salt: [UInt8] = []
    private static let bytes: [UInt8] = []
    // END EMBEDDED KEY

    // BEGIN EMBEDDED TELEMETRY (managed by tools/embed-key.sh --telemetry; keep empty in git)
    private static let telemetrySalt: [UInt8] = []
    private static let telemetryBytes: [UInt8] = []
    // END EMBEDDED TELEMETRY

    /// The decoded OpenRouter key, or nil in a build without one.
    static let openRouter: String? = decode(bytes, salt)

    /// The collector URL and its ingest key, or nil in a build without them.
    static let telemetry: (endpoint: URL, key: String)? = {
        guard let text = decode(telemetryBytes, telemetrySalt) else { return nil }
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2, let url = URL(string: parts[0]), url.scheme == "https", !parts[1].isEmpty else { return nil }
        return (url, parts[1])
    }()

    private static func decode(_ bytes: [UInt8], _ salt: [UInt8]) -> String? {
        guard !bytes.isEmpty, !salt.isEmpty else { return nil }
        let decoded = bytes.enumerated().map { $0.element ^ salt[$0.offset % salt.count] }
        guard let text = String(bytes: decoded, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }
}
