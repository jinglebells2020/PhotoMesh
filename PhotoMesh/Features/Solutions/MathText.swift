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

    /// Room around the typeset line so tall fractions and descenders are never clipped by the
    /// scroll view that hosts the label.
    private static let insets = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 4)

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.textAlignment = .left
        label.backgroundColor = .clear
        label.clipsToBounds = false
        label.contentInsets = MathLabel.insets
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        label.labelMode = display ? .display : .text
        label.fontSize = fontSize
        label.textColor = color
        label.latex = latex
        label.invalidateIntrinsicContentSize()
        label.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        // The label measures its typeset line itself (insets included); never let the container
        // squeeze it, or the fraction bars and numerators get cut.
        let measured = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let intrinsic = uiView.intrinsicContentSize
        let width = max(measured.width, intrinsic.width, 1)
        let height = max(measured.height, intrinsic.height, fontSize * 1.4)
        return CGSize(width: ceil(width), height: ceil(height))
    }
}
