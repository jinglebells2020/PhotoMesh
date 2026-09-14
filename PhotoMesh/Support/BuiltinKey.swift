import Foundation

/// The OpenRouter key baked into tester builds so nobody has to enter one.
///
/// The key is never committed: `tools/embed-key.sh` writes it here (XOR-obfuscated so it does not
/// sit in the binary as plain text) right before archiving, and the TestFlight workflow does the
/// same from the `OPENROUTER_TESTER_KEY` secret. In git both arrays stay empty, and a check in
/// the workflow fails the build if they are not. Obfuscation is not secrecy: anyone determined can
/// recover the key from the app, so give it a credit limit on openrouter.ai and rotate it freely.
enum BuiltinKey {
    // BEGIN EMBEDDED KEY (managed by tools/embed-key.sh; keep empty in git)
    private static let salt: [UInt8] = []
    private static let bytes: [UInt8] = []
    // END EMBEDDED KEY

    /// The decoded key, or nil in a build without one.
    static let openRouter: String? = {
        guard !bytes.isEmpty, !salt.isEmpty else { return nil }
        let decoded = bytes.enumerated().map { $0.element ^ salt[$0.offset % salt.count] }
        guard let key = String(bytes: decoded, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }()
}
