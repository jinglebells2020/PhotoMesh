import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal OpenRouter chat-completions client with image input and JSON-mode responses.
struct OpenRouterClient {
    struct Configuration: Hashable {
        var apiKey: String
        var model: String
        var timeout: TimeInterval = 90
        var endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case badStatus(Int, String)
        case emptyResponse(String)
        case network(Error)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your OpenRouter API key in Settings → Recognition to analyze photos."
            case .badStatus(let code, let message):
                switch code {
                case 401: return "OpenRouter rejected the API key. Check it in Settings → Recognition."
                case 402: return "The OpenRouter key has run out of credits."
                case 429: return "OpenRouter is rate limiting this key. Wait a moment and try again."
                default: return "OpenRouter returned an error (\(code)). \(message)"
                }
            case .emptyResponse(let detail):
                return "The model's answer could not be read. \(detail)"
            case .network(let error):
                let urlError = error as? URLError
                let code = urlError.map { " (code \($0.errorCode))" } ?? ""
                return "The connection to OpenRouter failed\(code): \(error.localizedDescription) Check your signal and try again."
            case .cancelled:
                return "The request was cancelled before the answer arrived."
            }
        }
    }

    let configuration: Configuration
    var session: URLSession = OpenRouterClient.makeSession()

    /// Generous timeouts and wait-for-connectivity: a recognition round trip is 10–20 s and must
    /// survive a brief cellular hiccup or the app being backgrounded for a moment.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 240
        #if canImport(Darwin)
        config.waitsForConnectivity = true
        #endif
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    /// Sends a system prompt, a user text and an optional JPEG; returns the assistant's text.
    func chatJSON(system: String, userText: String, imageJPEG: Data?) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var userContent: [[String: Any]] = [["type": "text", "text": userText]]
        if let imageJPEG {
            let dataURL = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
            userContent.append(["type": "image_url", "image_url": ["url": dataURL]])
        }
        let body: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.1,
            "max_tokens": 3000,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]

        var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://photomesh.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("PhotoMesh", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let started = Date()
        RecognitionLog.shared.record("request → \(configuration.model), \(imageJPEG.map { "\($0.count / 1024) KB image" } ?? "no image")")

        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let elapsed = String(format: "%.1f s", Date().timeIntervalSince(started))
                RecognitionLog.shared.record("response HTTP \(status) after \(elapsed), \(data.count) bytes")
                if (500...599).contains(status), attempt == 0 {
                    lastError = ClientError.badStatus(status, Self.errorMessage(in: data))
                    try await Task.sleep(for: .seconds(1.5))
                    continue
                }
                guard (200...299).contains(status) else {
                    throw ClientError.badStatus(status, Self.errorMessage(in: data))
                }
                let decoded: ChatResponse
                do {
                    decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
                } catch {
                    let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
                    RecognitionLog.shared.record("undecodable body: \(snippet)")
                    throw ClientError.emptyResponse("Unexpected response format.")
                }
                if let message = decoded.error?.message { throw ClientError.badStatus(status, message) }
                guard let content = decoded.choices?.first?.message.text, !content.isEmpty else {
                    let reason = decoded.choices?.first?.finishReason.map { "Finish reason: \($0)." } ?? "No content."
                    RecognitionLog.shared.record("empty content. \(reason)")
                    throw ClientError.emptyResponse(reason)
                }
                RecognitionLog.shared.record("content \(content.count) chars, finish=\(decoded.choices?.first?.finishReason ?? "?"), tokens=\(decoded.usage?.totalTokens.map(String.init) ?? "?")")
                return content
            } catch let error as ClientError {
                throw error
            } catch is CancellationError {
                RecognitionLog.shared.record("cancelled by the app")
                throw ClientError.cancelled
            } catch {
                let urlError = error as? URLError
                RecognitionLog.shared.record("transport error\(urlError.map { " \($0.errorCode)" } ?? ""): \(error.localizedDescription)")
                lastError = error
                if urlError?.code == .cancelled { throw ClientError.cancelled }
                // Retry only when the request most likely never reached the model; a retry re-sends the image.
                let retryable: Set<URLError.Code> = [.timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .secureConnectionFailed]
                if attempt == 0, let code = urlError?.code, retryable.contains(code) {
                    RecognitionLog.shared.record("retrying once")
                    try? await Task.sleep(for: .seconds(1.5))
                    continue
                }
                break
            }
        }
        throw ClientError.network(lastError ?? URLError(.unknown))
    }

    private static func errorMessage(in data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data), let message = decoded.error?.message {
            return message
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? ""
    }

    // MARK: Response shape

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: MessageContent?
                var text: String? { content?.text }
            }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
        struct APIError: Decodable {
            let message: String?
        }
        struct Usage: Decodable {
            let totalTokens: Int?
            enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
        }
        let choices: [Choice]?
        let error: APIError?
        let usage: Usage?
    }

    /// `content` is normally a string, but some providers return an array of parts.
    private enum MessageContent: Decodable {
        case text(String)
        case parts([String])

        var text: String {
            switch self {
            case .text(let s): return s
            case .parts(let parts): return parts.joined()
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else {
                struct Part: Decodable { let text: String? }
                let parts = try container.decode([Part].self)
                self = .parts(parts.compactMap(\.text))
            }
        }
    }
}

/// In-memory log of the last recognition round trips, shown under Settings → Recognition → Diagnostics.
final class RecognitionLog {
    static let shared = RecognitionLog()

    private let queue = DispatchQueue(label: "app.photomesh.recognition.log")
    private var entries: [String] = []
    private let limit = 60

    func record(_ message: String) {
        let stamp = RecognitionLog.timestamp.string(from: Date())
        queue.async {
            self.entries.append("\(stamp)  \(message)")
            if self.entries.count > self.limit { self.entries.removeFirst(self.entries.count - self.limit) }
        }
    }

    var text: String {
        queue.sync { entries.joined(separator: "\n") }
    }

    func clear() {
        queue.async { self.entries.removeAll() }
    }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
