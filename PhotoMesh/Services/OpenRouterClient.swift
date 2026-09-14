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
        /// Ask the model to think less: 2–3× faster, slightly less careful on messy pictures.
        var fastReasoning = false
        /// Output budget. Reasoning models spend hidden thinking tokens from the same budget,
        /// so this must be far larger than the JSON itself.
        var maxTokens = 16000
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
                return DeveloperOptions.enabled
                    ? "Add your OpenRouter API key in Settings → Recognition to analyze photos."
                    : "Photo recognition isn't set up in this build. Drawn circuits still solve."
            case .badStatus(let code, let message):
                switch code {
                case 401:
                    return DeveloperOptions.enabled
                        ? "OpenRouter rejected the API key. Check it in Settings → Recognition."
                        : "The recognition service rejected this build's key. Please tell us; drawn circuits still solve."
                case 402: return DeveloperOptions.enabled ? "The OpenRouter key has run out of credits." : "The shared beta key has run out of credit for now. Please tell us; drawn circuits still solve."
                case 429: return "The recognition service is busy right now. Wait a moment and try again."
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

    /// Assistant text plus what it cost.
    struct Completion {
        var text: String
        var model: String
        var promptTokens: Int?
        var completionTokens: Int?
        var reasoningTokens: Int?
        var finishReason: String?
        var latency: TimeInterval
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
        try await complete(system: system, userText: userText, imageJPEG: imageJPEG).text
    }

    /// Same as `chatJSON`, with token usage and timing.
    func complete(system: String, userText: String, imageJPEG: Data?) async throws -> Completion {
        guard !configuration.apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var userContent: [[String: Any]] = [["type": "text", "text": userText]]
        if let imageJPEG {
            let dataURL = "data:image/jpeg;base64," + imageJPEG.base64EncodedString()
            userContent.append(["type": "image_url", "image_url": ["url": dataURL]])
        }

        func makeRequest(maxTokens: Int) throws -> URLRequest {
            var body: [String: Any] = [
                "model": configuration.model,
                "temperature": 0.1,
                "max_tokens": maxTokens,
                "response_format": ["type": "json_object"],
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userContent],
                ],
            ]
            if configuration.fastReasoning { body["reasoning"] = ["effort": "low"] }
            var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
            request.httpMethod = "POST"
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://photomesh.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("PhotoMesh", forHTTPHeaderField: "X-Title")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        }

        let started = Date()
        var budget = configuration.maxTokens
        RecognitionLog.shared.record("request → \(configuration.model)\(configuration.fastReasoning ? " (fast)" : ""), \(imageJPEG.map { "\($0.count / 1024) KB image" } ?? "no image"), budget \(budget)")

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let request = try makeRequest(maxTokens: budget)
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
                let finish = decoded.choices?.first?.finishReason ?? "?"
                let usage = decoded.usage
                RecognitionLog.shared.record("finish=\(finish), tokens total \(usage?.totalTokens.map(String.init) ?? "?"), reasoning \(usage?.reasoningTokens.map(String.init) ?? "?")")
                if finish == "length", attempt < 2 {
                    // The hidden reasoning ate the budget; give it much more room and ask once more.
                    budget = min(budget * 2, 48000)
                    RecognitionLog.shared.record("answer truncated, retrying with budget \(budget)")
                    continue
                }
                guard let content = decoded.choices?.first?.message.text, !content.isEmpty else {
                    RecognitionLog.shared.record("empty content")
                    throw ClientError.emptyResponse("Finish reason: \(finish).")
                }
                if finish == "length" {
                    throw ClientError.emptyResponse("The answer was cut short twice. Try a tighter crop of the circuit.")
                }
                RecognitionLog.shared.record("content \(content.count) chars")
                return Completion(
                    text: content, model: configuration.model,
                    promptTokens: usage?.promptTokens, completionTokens: usage?.completionTokens, reasoningTokens: usage?.reasoningTokens,
                    finishReason: finish, latency: Date().timeIntervalSince(started)
                )
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
            struct Details: Decodable {
                let reasoningTokens: Int?
                enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
            }
            let totalTokens: Int?
            let promptTokens: Int?
            let completionTokens: Int?
            let completionDetails: Details?
            var reasoningTokens: Int? { completionDetails?.reasoningTokens }
            enum CodingKeys: String, CodingKey {
                case totalTokens = "total_tokens"
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case completionDetails = "completion_tokens_details"
            }
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
