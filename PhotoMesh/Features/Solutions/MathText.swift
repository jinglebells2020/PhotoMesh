import SwiftUI
import SwiftMath

/// Typeset mathematics. Renders LaTeX natively (SwiftMath, no web view) and falls back to the
/// plain line when the LaTeX does not parse, so a step can never come out blank.
struct MathText: View {
    let latex: String
    let fallback: String
    var fontSize: CGFloat = 16
    var color: Color = PMTheme.ink
    var display = true

    var body: some View {
        if MathText.parses(latex) {
            MathLabel(latex: latex, fontSize: fontSize, color: UIColor(color), display: display)
                .accessibilityLabel(fallback)
        } else {
            Text(fallback)
                .font(.system(size: fontSize, design: .rounded))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func parses(_ latex: String) -> Bool {
        MTMathListBuilder.build(fromString: latex) != nil
    }
}

private struct MathLabel: UIViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let color: UIColor
    let display: Bool

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.textAlignment = .left
        label.backgroundColor = .clear
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = color
        label.labelMode = display ? .display : .text
        label.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        let size = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}
