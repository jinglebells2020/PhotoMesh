import UIKit

/// Anything that can turn a capture or a typed problem into a `CircuitAnalysis`.
protocol CircuitSolverService {
    func solve(_ request: SolutionRequest, progress: @escaping (String) -> Void) async throws -> CircuitAnalysis
}

enum SolverProvider {
    /// Picks the solver for the current settings: sample mode, or the VLM when a key is configured.
    static func make() -> any CircuitSolverService {
        if APIConfiguration.useSampleCircuit { return SampleCircuitSolver() }
        if let key = APIConfiguration.apiKey, !key.isEmpty {
            return VLMCircuitSolver(configuration: OpenRouterClient.Configuration(apiKey: key, model: APIConfiguration.model))
        }
        return SampleCircuitSolver(reason: "No API key is set, so this is the built-in sample circuit. Add your OpenRouter key in Settings → Recognition to analyze your own photos.")
    }
}

// MARK: - Live solver

struct VLMCircuitSolver: CircuitSolverService {
    let configuration: OpenRouterClient.Configuration

    func solve(_ request: SolutionRequest, progress: @escaping (String) -> Void) async throws -> CircuitAnalysis {
        switch request.source {
        case .image(let image):
            progress("Reading the circuit…")
            let recognizer = CircuitRecognizer(client: OpenRouterClient(configuration: configuration))
            let recognized = try await recognizer.recognize(image)
            progress("Solving…")
            var notes = recognized.notes
            if let confidence = recognized.confidence, confidence < 0.7 {
                notes = ["The reader was not fully confident (\(Int(confidence * 100))%). Double-check the values below.", notes].compactMap { $0 }.joined(separator: " ")
            }
            return try CircuitAnalyzer.analyze(recognized.circuit, formatter: FormattingPreferences.formatter(), recognitionNotes: notes)
        case .expression(let text):
            return try ExpressionSolver.solve(text)
        }
    }
}

// MARK: - Offline sample

/// Runs the real engine on a built-in circuit so the whole flow works without a key or a camera.
struct SampleCircuitSolver: CircuitSolverService {
    var reason: String? = nil

    static let sample = Circuit(
        components: [
            Component(id: "V1", kind: .voltageSource, value: 10, nodeA: "n1", nodeB: "0"),
            Component(id: "R1", kind: .resistor, value: 2, nodeA: "n1", nodeB: "n2"),
            Component(id: "R2", kind: .resistor, value: 4, nodeA: "n2", nodeB: "0"),
            Component(id: "R3", kind: .resistor, value: 3, nodeA: "n2", nodeB: "n3"),
            Component(id: "V2", kind: .voltageSource, value: 5, nodeA: "n3", nodeB: "0"),
        ],
        groundNode: "0",
        meshes: [["V1", "R1", "R2"], ["R2", "R3", "V2"]],
        unknowns: [Unknown(kind: .current, element: "R2")],
        question: "Find the current through R2."
    )

    func solve(_ request: SolutionRequest, progress: @escaping (String) -> Void) async throws -> CircuitAnalysis {
        switch request.source {
        case .image:
            progress("Reading the circuit…")
            try await Task.sleep(for: .milliseconds(900))
            progress("Solving…")
            return try CircuitAnalyzer.analyze(Self.sample, formatter: FormattingPreferences.formatter(), recognitionNotes: reason ?? "Sample circuit (offline mode).")
        case .expression(let text):
            return try ExpressionSolver.solve(text)
        }
    }
}

// MARK: - Calculator path

enum ExpressionSolver {
    enum Failure: LocalizedError {
        case notEvaluable
        var errorDescription: String? { "This input can't be evaluated yet. Symbolic and circuit expressions are coming with the manual-entry update." }
    }

    static func solve(_ text: String) throws -> CircuitAnalysis {
        let sign = FormattingPreferences.decimalSign
        let evaluator = ExpressionEvaluator(decimalSign: sign)
        guard let value = try? evaluator.evaluate(text) else { throw Failure.notEvaluable }
        let formatted = ExpressionEvaluator.format(value, decimalSign: sign)
        let step = AnalysisStep(
            title: "Apply the order of operations",
            summary: text,
            equations: ["\(text) = \(formatted)"],
            explanation: "Parentheses first, then powers and roots, then multiplication and division, and finally addition and subtraction.",
            result: "= \(formatted)"
        )
        let method = MethodSolution(
            method: .arithmetic,
            headline: "= \(formatted)",
            steps: [step],
            nodeVoltages: [:],
            elements: [],
            answers: [Answer(label: "Result", value: formatted)]
        )
        return CircuitAnalysis(circuit: nil, question: "Evaluate \(text)", methods: [method], methodsAgree: true, recognitionNotes: nil)
    }
}
