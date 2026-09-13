import UIKit

/// Photo → `Circuit` via the vision-language model.
struct CircuitRecognizer {
    let client: OpenRouterClient

    struct Result {
        let circuit: Circuit
        let notes: String?
        let confidence: Double?
    }

    func recognize(_ image: UIImage) async throws -> Result {
        let jpeg = image.pmJPEGData(maxDimension: 1280, quality: 0.82)
        let text = try await client.chatJSON(system: RecognitionPrompt.system, userText: RecognitionPrompt.user, imageJPEG: jpeg)
        var payload: CircuitPayload
        do {
            payload = try CircuitPayload.parse(text)
        } catch {
            RecognitionLog.shared.record("unparseable model JSON: \(text.prefix(300))")
            throw CircuitPayload.PayloadError.unreadable
        }
        let size = image.size
        payload.aspectRatio = size.height > 0 ? Double(size.width / size.height) : 1.4
        let circuit = try payload.toCircuit()
        return Result(circuit: circuit, notes: payload.notes, confidence: payload.confidence)
    }
}

extension UIImage {
    /// Down-scales so the longest side is at most `maxDimension` and encodes as JPEG.
    func pmJPEGData(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let upright = orientedUp()
        let longest = max(upright.size.width, upright.size.height)
        guard longest > maxDimension else { return upright.jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let target = CGSize(width: (upright.size.width * scale).rounded(), height: (upright.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            upright.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
