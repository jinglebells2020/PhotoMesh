import Foundation

/// What a person changed when they corrected a recognized circuit: the shape of the reader's
/// mistakes, counted so the failure modes can be tallied without opening every sample.
struct CorrectionDiff: Codable, Hashable {
    /// Components in the correction that the reader did not produce.
    var added: Int = 0
    /// Components the reader produced that the correction dropped.
    var removed: Int = 0
    /// Same id, different kind (a lamp read as a resistor, a source flipped for a battery).
    var retyped: Int = 0
    /// Same id and kind, different value.
    var revalued: Int = 0
    /// Same id and kind, different terminals (including a source's polarity).
    var rewired: Int = 0
    var groundChanged: Bool = false
    var questionChanged: Bool = false
    var unknownsChanged: Bool = false

    var isEmpty: Bool {
        added == 0 && removed == 0 && retyped == 0 && revalued == 0 && rewired == 0 && !groundChanged && !questionChanged && !unknownsChanged
    }

    /// A short tag for grouping: the dominant kind of change.
    var dominant: String {
        let counts = [("rewired", rewired), ("revalued", revalued), ("retyped", retyped), ("added", added), ("removed", removed)]
        if let best = counts.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        if groundChanged { return "ground" }
        if unknownsChanged { return "unknowns" }
        if questionChanged { return "question" }
        return "none"
    }

    static func between(_ recognized: Circuit, _ corrected: Circuit) -> CorrectionDiff {
        var diff = CorrectionDiff()
        let before = Dictionary(recognized.components.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(corrected.components.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, new) in after {
            guard let old = before[id] else { diff.added += 1; continue }
            if old.kind != new.kind { diff.retyped += 1; continue }
            if abs(old.value - new.value) > 1e-12 * max(1, abs(old.value)) { diff.revalued += 1 }
            let sameWiring = old.kind.hasPolarity || old.kind.dcRole == .currentSource
                ? (old.nodeA == new.nodeA && old.nodeB == new.nodeB)
                : (Set([old.nodeA, old.nodeB]) == Set([new.nodeA, new.nodeB]))
            if !sameWiring { diff.rewired += 1 }
        }
        diff.removed = before.keys.filter { after[$0] == nil }.count
        diff.groundChanged = recognized.groundNode != corrected.groundNode
        diff.questionChanged = (recognized.question ?? "") != (corrected.question ?? "")
        diff.unknownsChanged = recognized.unknowns != corrected.unknowns
        return diff
    }

    /// Flat properties for an analytics event.
    var properties: [String: JSONValue] {
        ["added": .init(added), "removed": .init(removed), "retyped": .init(retyped), "revalued": .init(revalued), "rewired": .init(rewired),
         "ground": .init(groundChanged), "unknowns": .init(unknownsChanged), "dominant": .string(dominant)]
    }
}
