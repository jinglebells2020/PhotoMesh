import SwiftUI

/// Developer check for the typesetting: representative equation lines from every kind of step,
/// rendered exactly as the Solving Steps screen renders them, with a badge saying whether the
/// line went through SwiftMath or fell back to plain text.
struct MathPreviewView: View {
    private struct Sample: Identifiable {
        let id = UUID()
        let group: String
        let line: String
    }

    private let samples: [Sample] = [
        Sample(group: "KCL", line: "through R1 to a: (Vb − Va)/R1 = (Vb − 9)/1000"),
        Sample(group: "KCL", line: "Sum of currents leaving b = 0:  (Vb − 9)/1000 + Vb/2000 + Vb/2000 = 0"),
        Sample(group: "KCL", line: "× 2000:  2·(Vb − 9) + Vb + Vb = 0"),
        Sample(group: "KCL", line: "→ 4·Vb = 18"),
        Sample(group: "KCL", line: "I1 pushes 3 A into b: −3"),
        Sample(group: "KVL", line: "V1 (crossed − to +, a rise): −9"),
        Sample(group: "KVL", line: "R2 (shared with mesh 2): +2000·(I₁ − I₂)"),
        Sample(group: "KVL", line: "Expand:  −9 + 1000·I₁ + 2000·I₁ − 2000·I₂ = 0"),
        Sample(group: "Solving", line: "(1)  3000·I₁ − 2000·I₂ = 9"),
        Sample(group: "Solving", line: "3×(2): 6000·I₁ + 12000·I₂ = 0"),
        Sample(group: "Solving", line: "→ (1′)  −8000·I₂ = 18"),
        Sample(group: "Solving", line: "I₂ = 18/(−8000)"),
        Sample(group: "Solving", line: "17·Vb − 2·5.935 = 100"),
        Sample(group: "Solving", line: "→ Vb = 571.4 mV"),
        Sample(group: "Results", line: "I(R1) = (12 − 8.25)/100 = 37.5 mA  (from a to b)"),
        Sample(group: "Results", line: "V(R1) = R1·I(R1) = 100 Ω·37.5 mA = 3.75 V"),
        Sample(group: "Results", line: "I(R2) = I₁ − I₂ = 1.923 A + (−384.6 mA) = 1.538 A"),
        Sample(group: "Results", line: "I(V1): KCL at a → I(R1) = 4.5 mA leaves through the other elements, so V1 delivers 4.5 mA"),
        Sample(group: "Check", line: "P(R1) = I²·R = (4.5 mA)²·1 kΩ = 20.25 mW"),
        Sample(group: "Check", line: "Absorbed: 20.25 mW + 10.12 mW + 10.12 mW = 40.5 mW"),
        Sample(group: "Check", line: "→ delivered = absorbed ✓"),
        Sample(group: "Check", line: "KCL at b: in 4.5 mA = 4.5 mA, out 2.25 mA + 2.25 mA = 4.5 mA ✓"),
        Sample(group: "Simplify", line: "R2 ‖ R3: both between b and 0"),
        Sample(group: "Simplify", line: "R23 = (R2·R3)/(R2 + R3) = (2000·2000)/(2000 + 2000) = 1 kΩ"),
        Sample(group: "Simplify", line: "R1 — b — R23: nothing else connects at b"),
        Sample(group: "Simplify", line: "Series: R = R₁ + R₂ (same current)"),
        Sample(group: "DC redraw", line: "L1 (inductor): short circuit → V(L1) = 0, node c is node b"),
        Sample(group: "DC redraw", line: "C1 = 10 µF between c and 0"),
        Sample(group: "Calculator", line: "√(16)+2^3 = 12"),
        Sample(group: "Calculator", line: "1.5×10^13 = 1.5×10^13"),
    ]

    private var groups: [String] {
        var seen: [String] = []
        for sample in samples where !seen.contains(sample.group) { seen.append(sample.group) }
        return seen
    }

    private var fallbackCount: Int {
        samples.filter { !MathText.parses(EquationLaTeX.latex(for: $0.line)) }.count
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: fallbackCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(fallbackCount == 0 ? PMTheme.accent : PMTheme.whyOrange)
                    Text(fallbackCount == 0 ? "All \(samples.count) sample lines typeset" : "\(fallbackCount) of \(samples.count) lines fell back to plain text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PMTheme.ink)
                }
            } footer: {
                Text("Each line is rendered the way the Solving Steps screen renders it. \"TeX\" means SwiftMath typeset it; \"plain\" means it could not parse the LaTeX and the original text is shown instead. Long lines scroll sideways.")
            }
            ForEach(groups, id: \.self) { group in
                Section(group.uppercased()) {
                    ForEach(samples.filter { $0.group == group }) { sample in
                        let latex = EquationLaTeX.latex(for: sample.line)
                        let typeset = MathText.parses(latex)
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                MathText(latex: latex, fallback: sample.line, fontSize: 15.5)
                                    .padding(.vertical, 2)
                            }
                            HStack(spacing: 6) {
                                Text(typeset ? "TeX" : "plain")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(typeset ? PMTheme.accent : PMTheme.whyOrange))
                                Text(latex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(PMTheme.tertiaryText)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Typesetting preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
