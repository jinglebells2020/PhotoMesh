import Foundation

// MARK: - Circuit description ("calculable form")

enum ComponentKind: String, Codable, Hashable {
    case resistor
    case voltageSource = "voltage_source"
    case currentSource = "current_source"

    var unitSymbol: String {
        switch self {
        case .resistor: return "Ω"
        case .voltageSource: return "V"
        case .currentSource: return "A"
        }
    }

    var displayName: String {
        switch self {
        case .resistor: return "Resistor"
        case .voltageSource: return "Voltage source"
        case .currentSource: return "Current source"
        }
    }
}

/// A two-terminal element.
///
/// Terminal convention:
/// - resistor: any order.
/// - voltage source: `nodeA` is the positive terminal, `nodeB` the negative one (V(nodeA) − V(nodeB) = value).
/// - current source: the current flows *inside* the source from `nodeA` to `nodeB` (the arrow points at `nodeB`).
///
/// Every computed element current uses the same convention: positive when flowing from `nodeA` to `nodeB`
/// through the element.
struct Component: Identifiable, Hashable, Codable {
    var id: String
    var kind: ComponentKind
    var value: Double
    var nodeA: String
    var nodeB: String

    func otherNode(_ node: String) -> String { node == nodeA ? nodeB : nodeA }
    func touches(_ node: String) -> Bool { nodeA == node || nodeB == node }
}

/// What the problem asks for.
struct Unknown: Hashable, Codable {
    enum Kind: String, Codable, Hashable {
        case current, voltage, power, resistance
    }

    var kind: Kind
    var element: String?
    var node: String?
    var between: [String]?
}

struct Circuit: Hashable, Codable {
    var components: [Component]
    var groundNode: String
    /// Optional mesh hints (component ids per mesh) from the recognizer; verified before use.
    var meshes: [[String]] = []
    var unknowns: [Unknown] = []
    var question: String?
    var notes: String?
    var unsupported: [String] = []
    /// Symbol positions from the picture or the sketch canvas; drives the schematic drawing.
    var geometry: CircuitGeometry? = nil

    /// All node ids, ground first, the rest in natural order.
    var nodes: [String] {
        var seen: [String] = []
        for component in components {
            for node in [component.nodeA, component.nodeB] where !seen.contains(node) {
                seen.append(node)
            }
        }
        let others = seen.filter { $0 != groundNode }.sorted(by: Circuit.naturalOrder)
        return (seen.contains(groundNode) ? [groundNode] : []) + others
    }

    var resistors: [Component] { components.filter { $0.kind == .resistor } }
    var voltageSources: [Component] { components.filter { $0.kind == .voltageSource } }
    var currentSources: [Component] { components.filter { $0.kind == .currentSource } }

    func component(_ id: String) -> Component? { components.first { $0.id == id } }

    func components(at node: String) -> [Component] { components.filter { $0.touches(node) } }

    static func naturalOrder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}

// MARK: - Validation

enum CircuitValidationError: LocalizedError, Equatable {
    case noComponents
    case noSource
    case unsupportedElements([String])
    case shortedSource(String)
    case nonPositiveResistor(String)
    case disconnected
    case danglingElement(String)
    case missingGround

    var errorDescription: String? {
        switch self {
        case .noComponents:
            return "No components were recognized in the picture."
        case .noSource:
            return "The circuit has no voltage or current source, so there is nothing to solve."
        case .unsupportedElements(let ids):
            return "This version solves DC circuits with resistors and independent sources. Not supported yet: \(ids.joined(separator: ", "))."
        case .shortedSource(let id):
            return "\(id) has both terminals on the same node (it is shorted)."
        case .nonPositiveResistor(let id):
            return "\(id) needs a positive resistance value."
        case .disconnected:
            return "The circuit is not fully connected. Check for a missing wire."
        case .danglingElement(let id):
            return "\(id) is connected on one side only, so no current can flow through it."
        case .missingGround:
            return "Could not determine a reference node."
        }
    }
}

extension Circuit {
    /// Cleans up trivial issues (duplicate ids, resistors shorted by a wire) and throws on anything unsolvable.
    func validated() throws -> Circuit {
        guard !components.isEmpty else { throw CircuitValidationError.noComponents }
        if !unsupported.isEmpty { throw CircuitValidationError.unsupportedElements(unsupported) }

        var cleaned = self
        // Drop resistors whose two ends are the same node: they carry no current.
        cleaned.components.removeAll { $0.kind == .resistor && $0.nodeA == $0.nodeB }

        for component in cleaned.components {
            if component.kind != .resistor, component.nodeA == component.nodeB {
                throw CircuitValidationError.shortedSource(component.id)
            }
            if component.kind == .resistor, !(component.value > 0) {
                throw CircuitValidationError.nonPositiveResistor(component.id)
            }
        }

        guard cleaned.components.contains(where: { $0.kind != .resistor }) else {
            throw CircuitValidationError.noSource
        }

        let nodes = cleaned.nodes
        guard nodes.contains(cleaned.groundNode) else {
            // Fall back to the negative terminal of the first voltage source, else the busiest node.
            if let source = cleaned.voltageSources.first {
                cleaned.groundNode = source.nodeB
            } else if let busiest = nodes.max(by: { cleaned.components(at: $0).count < cleaned.components(at: $1).count }) {
                cleaned.groundNode = busiest
            } else {
                throw CircuitValidationError.missingGround
            }
            return try cleaned.validated()
        }

        for node in nodes where cleaned.components(at: node).count < 2 {
            if let lonely = cleaned.components(at: node).first {
                throw CircuitValidationError.danglingElement(lonely.id)
            }
        }

        guard CircuitGraph(cleaned).isConnected else { throw CircuitValidationError.disconnected }
        return cleaned
    }
}

// MARK: - Graph helpers

/// Undirected multigraph view of a circuit: vertices are nodes, edges are components.
struct CircuitGraph {
    let nodes: [String]
    let components: [Component]
    private let adjacency: [String: [(edge: Int, neighbor: String)]]

    init(_ circuit: Circuit) {
        nodes = circuit.nodes
        components = circuit.components
        var adjacency: [String: [(edge: Int, neighbor: String)]] = [:]
        for (index, component) in components.enumerated() {
            adjacency[component.nodeA, default: []].append((index, component.nodeB))
            adjacency[component.nodeB, default: []].append((index, component.nodeA))
        }
        self.adjacency = adjacency
    }

    func neighbors(of node: String) -> [(edge: Int, neighbor: String)] {
        adjacency[node] ?? []
    }

    var isConnected: Bool {
        guard let start = nodes.first else { return true }
        var visited: Set<String> = [start]
        var queue = [start]
        while let node = queue.popLast() {
            for (_, next) in neighbors(of: node) where !visited.contains(next) {
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited.count == nodes.count
    }

    /// Shortest paths (in number of edges) from `source`. Returns, per node, the edge used to reach it and its predecessor.
    func shortestPathTree(from source: String) -> [String: (edge: Int, previous: String)] {
        var tree: [String: (edge: Int, previous: String)] = [:]
        var visited: Set<String> = [source]
        var queue = [source]
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for (edge, next) in neighbors(of: node) where !visited.contains(next) {
                visited.insert(next)
                tree[next] = (edge, node)
                queue.append(next)
            }
        }
        return tree
    }

    /// Edge indices along the tree path from `source` to `target` (empty when equal).
    func path(in tree: [String: (edge: Int, previous: String)], to target: String) -> [Int] {
        var edges: [Int] = []
        var node = target
        while let step = tree[node] {
            edges.append(step.edge)
            node = step.previous
        }
        return edges.reversed()
    }
}
