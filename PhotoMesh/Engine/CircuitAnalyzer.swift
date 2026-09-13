import Foundation

enum CircuitAnalyzerError: LocalizedError {
    case allMethodsFailed(String)

    var errorDescription: String? {
        switch self {
        case .allMethodsFailed(let reason): return reason
        }
    }
}

/// Runs every applicable method on a recognized circuit and cross-checks the results.
enum CircuitAnalyzer {
    static func analyze(_ raw: Circuit, formatter: QuantityFormatter = QuantityFormatter(), recognitionNotes: String? = nil) throws -> CircuitAnalysis {
        let circuit = try raw.validated()
        var methods: [MethodSolution] = []
        var failures: [String] = []

        do {
            methods.append(try NodalAnalysis.solve(circuit, formatter: formatter))
        } catch {
            failures.append("Nodal analysis: \(error.localizedDescription)")
        }
        do {
            methods.append(try MeshAnalysis.solve(circuit, formatter: formatter))
        } catch {
            failures.append("Mesh analysis: \(error.localizedDescription)")
        }

        guard !methods.isEmpty else {
            throw CircuitAnalyzerError.allMethodsFailed(failures.joined(separator: "\n"))
        }

        return CircuitAnalysis(
            circuit: circuit,
            question: circuit.question ?? defaultQuestion(for: circuit),
            methods: methods,
            methodsAgree: agree(methods),
            recognitionNotes: recognitionNotes
        )
    }

    static func agree(_ methods: [MethodSolution]) -> Bool {
        guard let first = methods.first else { return false }
        for other in methods.dropFirst() {
            for (a, b) in zip(first.elements, other.elements) {
                let scale = max(abs(a.current), abs(b.current), 1e-9)
                if abs(a.current - b.current) / scale > 1e-6 { return false }
            }
        }
        return true
    }

    private static func defaultQuestion(for circuit: Circuit) -> String {
        "Find the current through every element"
    }
}
