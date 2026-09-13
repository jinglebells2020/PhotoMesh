import Foundation

/// Tolerant decoder for the JSON the recognizer returns (numbers may arrive as strings, node ids as numbers).
struct CircuitPayload: Decodable {
    struct ComponentPayload: Decodable {
        var id: String
        var type: String
        var value: FlexibleNumber?
        var nodeA: FlexibleString?
        var nodeB: FlexibleString?
        var positiveNode: FlexibleString?
        var negativeNode: FlexibleString?
        var fromNode: FlexibleString?
        var toNode: FlexibleString?

        enum CodingKeys: String, CodingKey {
            case id, type, value
            case nodeA = "node_a", nodeB = "node_b"
            case positiveNode = "positive_node", negativeNode = "negative_node"
            case fromNode = "from_node", toNode = "to_node"
        }
    }

    struct UnknownPayload: Decodable {
        var kind: String
        var element: FlexibleString?
        var node: FlexibleString?
        var between: [FlexibleString]?
    }

    var error: String?
    var components: [ComponentPayload]?
    var groundNode: FlexibleString?
    var meshes: [[String]]?
    var unknowns: [UnknownPayload]?
    var question: String?
    var unsupported: [String]?
    var confidence: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case error, components, meshes, unknowns, question, unsupported, confidence, notes
        case groundNode = "ground_node"
    }

    enum PayloadError: LocalizedError {
        case noCircuit
        case badComponent(String)
        case missingValue(String)

        var errorDescription: String? {
            switch self {
            case .noCircuit: return "No circuit was found in the picture. Try to frame the whole diagram inside the white corners."
            case .badComponent(let id): return "The reader could not tell where \(id) is connected."
            case .missingValue(let id): return "The value of \(id) could not be read. Make sure the labels are sharp and inside the frame."
            }
        }
    }

    /// Parses the model output, tolerating markdown fences around the JSON.
    static func parse(_ text: String) throws -> CircuitPayload {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let range = body.range(of: "```", options: .backwards) { body = String(body[..<range.lowerBound]) }
        }
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}") {
            body = String(body[start...end])
        }
        return try JSONDecoder().decode(CircuitPayload.self, from: Data(body.utf8))
    }

    func toCircuit() throws -> Circuit {
        if let error, !error.isEmpty { throw PayloadError.noCircuit }
        guard let components, !components.isEmpty else { throw PayloadError.noCircuit }

        var converted: [Component] = []
        var usedIds: Set<String> = []
        for payload in components {
            var id = payload.id.trimmingCharacters(in: .whitespaces)
            if id.isEmpty { id = "X\(converted.count + 1)" }
            while usedIds.contains(id) { id += "'" }
            usedIds.insert(id)

            let kind: ComponentKind
            switch payload.type.lowercased().replacingOccurrences(of: " ", with: "_") {
            case "resistor", "r": kind = .resistor
            case "voltage_source", "voltagesource", "battery", "dc_voltage_source", "v": kind = .voltageSource
            case "current_source", "currentsource", "dc_current_source", "i": kind = .currentSource
            default: continue   // unsupported kinds are reported separately by the model
            }

            guard let value = payload.value?.value else { throw PayloadError.missingValue(id) }
            let a: String?
            let b: String?
            switch kind {
            case .resistor:
                a = payload.nodeA?.value ?? payload.positiveNode?.value ?? payload.fromNode?.value
                b = payload.nodeB?.value ?? payload.negativeNode?.value ?? payload.toNode?.value
            case .voltageSource:
                a = payload.positiveNode?.value ?? payload.nodeA?.value
                b = payload.negativeNode?.value ?? payload.nodeB?.value
            case .currentSource:
                a = payload.fromNode?.value ?? payload.nodeA?.value
                b = payload.toNode?.value ?? payload.nodeB?.value
            }
            guard let nodeA = a, let nodeB = b, !nodeA.isEmpty, !nodeB.isEmpty else { throw PayloadError.badComponent(id) }
            converted.append(Component(id: id, kind: kind, value: value, nodeA: nodeA, nodeB: nodeB))
        }

        let unknowns: [Unknown] = (self.unknowns ?? []).compactMap { payload in
            guard let kind = Unknown.Kind(rawValue: payload.kind.lowercased()) else { return nil }
            return Unknown(kind: kind, element: payload.element?.value, node: payload.node?.value, between: payload.between?.map(\.value))
        }

        return Circuit(
            components: converted,
            groundNode: groundNode?.value ?? "0",
            meshes: meshes ?? [],
            unknowns: unknowns,
            question: question?.isEmpty == false ? question : nil,
            notes: notes,
            unsupported: unsupported ?? []
        )
    }
}

/// Decodes a number written either as a JSON number or as a string like "4.7k".
struct FlexibleNumber: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = QuantityFormatter.parseValue(text)
        } else {
            value = nil
        }
    }
}

/// Decodes a string that may have been emitted as a number (node "0" → 0).
struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text.trimmingCharacters(in: .whitespaces)
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else if let number = try? container.decode(Double.self) {
            value = number == number.rounded() ? String(Int(number)) : String(number)
        } else {
            value = ""
        }
    }
}
