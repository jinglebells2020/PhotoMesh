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
        case emptyResponse
        case network(Error)

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
            case .emptyResponse:
                return "The model returned an empty answer. Try taking the picture again."
            case .network(let error):
                return "Network problem: \(error.localizedDescription)"
            }
        }
    }

    let configuration: Configuration
    var session: URLSession = .shared

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

        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (500...599).contains(status), attempt == 0 {
                    lastError = ClientError.badStatus(status, Self.errorMessage(in: data))
                    try await Task.sleep(for: .seconds(1.5))
                    continue
                }
                guard (200...299).contains(status) else {
                    throw ClientError.badStatus(status, Self.errorMessage(in: data))
                }
                let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
                if let message = decoded.error?.message { throw ClientError.badStatus(status, message) }
                guard let content = decoded.choices?.first?.message.text, !content.isEmpty else {
                    throw ClientError.emptyResponse
                }
                return content
            } catch let error as ClientError {
                throw error
            } catch is DecodingError {
                throw ClientError.emptyResponse
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(1.5))
                    continue
                }
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
        }
        struct APIError: Decodable {
            let message: String?
        }
        let choices: [Choice]?
        let error: APIError?
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
