import Foundation

enum AnalysisMethod: String, Codable, Hashable, CaseIterable {
    case reduction
    case nodal
    case mesh
    case arithmetic

    var eyebrow: String {
        switch self {
        case .reduction: return "SERIES & PARALLEL"
        case .nodal: return "NODAL ANALYSIS"
        case .mesh: return "MESH ANALYSIS"
        case .arithmetic: return "SOLVING STEPS"
        }
    }

    var title: String {
        switch self {
        case .reduction: return "Simplify step by step"
        case .nodal: return "Node-voltage method"
        case .mesh: return "Mesh-current method"
        case .arithmetic: return "Evaluate the expression"
        }
    }

    var summary: String {
        switch self {
        case .reduction: return "Combine resistors that are in series or in parallel until one is left, apply Ohm's law, then work back out."
        case .nodal: return "Write KCL at each node, solve for the node voltages, then read off every current."
        case .mesh: return "Assign a clockwise current to each mesh, write KVL around each one, then combine them for every element."
        case .arithmetic: return "Apply the order of operations."
        }
    }
}

/// What the schematic should show while a step is open.
struct StepFocus: Hashable {
    var nodes: [String] = []
    var elements: [String] = []
    /// Indices into `MethodSolution.loops`.
    var loops: [Int] = []
    /// Zoom the schematic window onto the focused items (otherwise show the whole circuit).
    var zoom = false
    var nodeVoltages: [String: Double] = [:]
    var elementCurrents: [String: Double] = [:]
    var meshCurrents: [Int: Double] = [:]
    var showMeshArrows = false
    /// Show the currents moving: dots travel along wires and elements (or around meshes) in the
    /// direction the current really flows, faster where it is larger.
    var animateCurrents = false
    /// Mark + and − across each element whose current is known (voltage steps).
    var showPolarity = false
    /// Groups of nodes to draw a dashed boundary around, with the sources tying them together.
    var supernodes: [Supernode] = []

    var isEmpty: Bool { nodes.isEmpty && elements.isEmpty && loops.isEmpty }
}

/// Nodes joined by floating voltage sources that KCL treats as one region.
struct Supernode: Hashable {
    var nodes: [String]
    var elements: [String]
}

/// A mesh / loop as element ids in traversal order, for drawing circulating arrows.
struct LoopPath: Hashable {
    var elementIds: [String]
    var nodeSequence: [String]
}

/// One step in a walkthrough. `equations` are rendered as separate lines under the title.
struct AnalysisStep: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var summary: String
    var equations: [String] = []
    var explanation: String
    var result: String
    var focus = StepFocus()
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
    var loops: [LoopPath] = []
}

/// Everything the UI needs after a solve.
struct CircuitAnalysis: Hashable {
    var circuit: Circuit?
    var question: String
    var methods: [MethodSolution]
    /// True when every method agrees on the element currents.
    var methodsAgree: Bool
    var recognitionNotes: String?
    /// Drawing of the recognized circuit, nil for calculator results.
    var layout: SchematicLayout? = nil
}
