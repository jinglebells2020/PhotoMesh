import UIKit

// MARK: - Models

struct Solution: Identifiable, Hashable {
    let id = UUID()
    let category: String
    let title: String
    let problem: String
    let approach: String
    let result: String
    let steps: [SolutionStep]
    let detail: CircuitDetail?
}

struct SolutionStep: Identifiable, Hashable {
    let id = UUID()
    let expression: String
    let description: String
    let explanation: String
    let result: String
}

struct CircuitDetail: Hashable {
    let title: String
    let subtitle: String
    let properties: [CircuitProperty]
    let sketch: CircuitSketchKind
}

struct CircuitProperty: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: String
}

enum CircuitSketchKind: Hashable {
    case seriesTwoResistors
    case blank
}

// MARK: - Service

/// Anything that can turn a capture or a typed problem into a `Solution`.
/// The VLM-backed implementation will conform to this protocol in the next phase.
protocol CircuitSolverService {
    func solve(_ request: SolutionRequest) async throws -> Solution
}

enum SolverProvider {
    /// Swap this for the API-backed solver once it exists.
    static var current: any CircuitSolverService = MockCircuitSolver()
}

/// Returns canned content after a short delay so the whole UI flow can be exercised.
struct MockCircuitSolver: CircuitSolverService {
    func solve(_ request: SolutionRequest) async throws -> Solution {
        try await Task.sleep(for: .milliseconds(1100))
        switch request.source {
        case .image:
            return MockCircuitSolver.seriesLoop
        case .expression(let expression):
            return MockCircuitSolver.solution(for: expression)
        }
    }

    static let seriesLoop = Solution(
        category: "SOLVING STEPS",
        title: "Find the loop current",
        problem: "V = 12 V, R₁ = 100 Ω, R₂ = 220 Ω in series",
        approach: "Combine the series resistors, then apply Ohm's law",
        result: "I = 37.5 mA",
        steps: [
            SolutionStep(
                expression: "Rₑq = R₁ + R₂",
                description: "Combine the series resistors",
                explanation: "Resistors in series carry the same current, so their resistances simply add up.",
                result: "Rₑq = 100 Ω + 220 Ω = 320 Ω"
            ),
            SolutionStep(
                expression: "I = V ÷ Rₑq",
                description: "Apply Ohm's law to the whole loop",
                explanation: "One source drives one loop, so the loop current is the source voltage divided by the equivalent resistance.",
                result: "I = 12 V ÷ 320 Ω"
            ),
            SolutionStep(
                expression: "I = 0.0375 A",
                description: "Simplify",
                explanation: "Divide, then express the result in a convenient engineering unit.",
                result: "I = 37.5 mA"
            ),
        ],
        detail: CircuitDetail(
            title: "Series loop",
            subtitle: "12 V source, R₁ = 100 Ω, R₂ = 220 Ω",
            properties: [
                CircuitProperty(name: "Equivalent resistance", value: "320 Ω"),
                CircuitProperty(name: "Loop current", value: "37.5 mA"),
                CircuitProperty(name: "Voltage across R₁", value: "3.75 V"),
                CircuitProperty(name: "Voltage across R₂", value: "8.25 V"),
                CircuitProperty(name: "Total power", value: "450 mW"),
            ],
            sketch: .seriesTwoResistors
        )
    )

    static func solution(for expression: String) -> Solution {
        let decimal = UserDefaults.standard.string(forKey: SettingsKeys.decimalSign) == DecimalSign.comma.rawValue ? Character(",") : Character(".")
        let evaluator = ExpressionEvaluator(decimalSign: decimal)
        if let value = try? evaluator.evaluate(expression) {
            let formatted = ExpressionEvaluator.format(value, decimalSign: decimal)
            return Solution(
                category: "SOLVING STEPS",
                title: "Evaluate the expression",
                problem: expression,
                approach: "Evaluate \(expression)",
                result: "= \(formatted)",
                steps: [
                    SolutionStep(
                        expression: expression,
                        description: "Apply the order of operations",
                        explanation: "Work through parentheses first, then powers and roots, then multiplication and division, and finally addition and subtraction.",
                        result: "= \(formatted)"
                    ),
                ],
                detail: nil
            )
        }
        return Solution(
            category: "SOLVING STEPS",
            title: "Interpret the input",
            problem: expression,
            approach: "This input needs the full circuit solver",
            result: "Coming soon",
            steps: [
                SolutionStep(
                    expression: expression,
                    description: "Recognized input",
                    explanation: "Symbolic and circuit problems will be handled by the analysis engine in the next release.",
                    result: "Coming soon"
                ),
            ],
            detail: nil
        )
    }
}
