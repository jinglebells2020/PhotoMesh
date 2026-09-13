import Foundation

enum AnalysisMethod: String, Codable, Hashable, CaseIterable {
    case nodal
    case mesh
    case arithmetic

    var eyebrow: String {
        switch self {
        case .nodal: return "NODAL ANALYSIS"
        case .mesh: return "MESH ANALYSIS"
        case .arithmetic: return "SOLVING STEPS"
        }
    }

    var title: String {
        switch self {
        case .nodal: return "Node-voltage method"
        case .mesh: return "Mesh-current method"
        case .arithmetic: return "Evaluate the expression"
        }
    }

    var summary: String {
        switch self {
        case .nodal: return "Write KCL at each node, solve for the node voltages, then read off every current."
        case .mesh: return "Assign a current to each mesh, write KVL around each one, then combine them for every element."
        case .arithmetic: return "Apply the order of operations."
        }
    }
}

/// One step in a walkthrough. `equations` are rendered as separate lines under the title.
struct AnalysisStep: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var summary: String
    var equations: [String] = []
    var explanation: String
    var result: String
}

/// Per-element outcome. Current is positive from `nodeA` to `nodeB` through the element;
/// voltage is V(nodeA) − V(nodeB).
struct ElementResult: Identifiable, Hashable {
    let id: String
    let kind: ComponentKind
    let value: Double
    let nodeA: String
    let nodeB: String
    let current: Double
    let voltage: Double

    var power: Double { current * voltage }
}

struct Answer: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var value: String
}

struct MethodSolution: Identifiable, Hashable {
    let id = UUID()
    var method: AnalysisMethod
    var headline: String            // e.g. "I(R2) = 37.5 mA"
    var steps: [AnalysisStep]
    var nodeVoltages: [String: Double]
    var elements: [ElementResult]
    var answers: [Answer]
}

/// Everything the UI needs after a solve.
struct CircuitAnalysis: Hashable {
    var circuit: Circuit?
    var question: String
    var methods: [MethodSolution]
    /// True when every method agrees on the element currents.
    var methodsAgree: Bool
    var recognitionNotes: String?
}
