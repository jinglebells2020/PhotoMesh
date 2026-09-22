import SwiftUI
import UIKit
import SwiftMath

/// Renders a walkthrough to an A4 PDF: the question and the circuit drawing on the first page,
/// then every step with its equations typeset the way the app shows them, and the answers.
@MainActor
enum StepsPDFExporter {
    private static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let margin: CGFloat = 46
    private static var contentWidth: CGFloat { page.width - 2 * margin }

    static func export(analysis: CircuitAnalysis, solution: MethodSolution) throws -> URL {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: analysis.question,
            kCGPDFContextCreator as String: "PhotoMesh",
            kCGPDFContextSubject as String: solution.method.title,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let schematic = schematicImage(analysis: analysis, solution: solution)
        let data = renderer.pdfData { context in
            let writer = PageWriter(context: context)
            writer.beginPage()
            writer.text("PhotoMesh · \(solution.method.title)", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabel, spacingAfter: 6)
            writer.text(analysis.question, font: .systemFont(ofSize: 20, weight: .bold), color: .label, spacingAfter: 6)
            writer.text(Date().formatted(date: .long, time: .shortened), font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
            if let schematic { writer.image(schematic, maxHeight: 250, spacingAfter: 14) }
            if let circuit = analysis.circuit {
                let formatter = FormattingPreferences.formatter()
                let given = circuit.components.map { "\($0.id): \($0.kind.valueText($0.value, formatter: formatter)) between \($0.nodeA) and \($0.nodeB)" }
                writer.text("Given", font: .systemFont(ofSize: 12, weight: .semibold), color: .label, spacingAfter: 3)
                writer.text(given.joined(separator: "\n"), font: .systemFont(ofSize: 10.5), color: .label, spacingAfter: 14)
            }
            writer.rule()
            for (index, step) in solution.steps.enumerated() {
                writer.keepTogether(minimumHeight: 70)
                writer.text("\(index + 1). \(step.title)", font: .systemFont(ofSize: 13.5, weight: .semibold), color: .label, spacingAfter: 2)
                writer.text(step.summary, font: .systemFont(ofSize: 10.5), color: .secondaryLabel, spacingAfter: 6)
                for line in step.equations {
                    writer.math(line, indent: 10)
                }
                writer.text(step.explanation, font: .systemFont(ofSize: 10.5), color: .darkGray, spacingAfter: 4, indent: 10)
                writer.text(step.result, font: .systemFont(ofSize: 11, weight: .semibold), color: UIColor(PMTheme.accent), spacingAfter: 12, indent: 10)
            }
            writer.rule()
            writer.keepTogether(minimumHeight: 60)
            writer.text("Solution", font: .systemFont(ofSize: 15, weight: .bold), color: UIColor(PMTheme.accent), spacingAfter: 6)
            if solution.answers.isEmpty {
                writer.text(solution.headline, font: .systemFont(ofSize: 13, weight: .semibold), color: .label, spacingAfter: 4)
            } else {
                for answer in solution.answers {
                    writer.text(answer.label, font: .systemFont(ofSize: 10.5), color: .secondaryLabel, spacingAfter: 1)
                    writer.text(answer.value, font: .systemFont(ofSize: 14, weight: .bold), color: .label, spacingAfter: 8)
                }
            }
            writer.finish()
        }
        let base = SpiceExport.safeBaseName(analysis.question)
        let url = CircuitExports.folder.appendingPathComponent("\(base)-\(solution.method.rawValue)-steps.pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The circuit with its solved voltages and currents, drawn off-screen.
    private static func schematicImage(analysis: CircuitAnalysis, solution: MethodSolution) -> UIImage? {
        guard let layout = analysis.layout else { return nil }
        var focus = StepFocus()
        focus.nodeVoltages = solution.nodeVoltages
        focus.elementCurrents = Dictionary(uniqueKeysWithValues: solution.elements.map { ($0.id, $0.current) })
        let size = CGSize(width: 1000, height: 560)
        let view = ZStack {
            Color.white
            SchematicView(layout: layout, style: SchematicStyle(focus: focus, loops: solution.loops, formatter: FormattingPreferences.formatter()), camera: .fitting(layout.bounds, in: size, padding: 24))
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// Keeps a cursor down the page and starts new pages as needed.
@MainActor
private final class PageWriter {
    private let context: UIGraphicsPDFRendererContext
    private var y: CGFloat = 0
    private var pageNumber = 0
    private let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let margin: CGFloat = 46
    private var contentWidth: CGFloat { page.width - 2 * margin }
    private var bottom: CGFloat { page.height - margin - 18 }

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    func beginPage() {
        if pageNumber > 0 { footer() }
        context.beginPage()
        pageNumber += 1
        y = margin
    }

    func finish() { footer() }

    private func footer() {
        let text = NSAttributedString(string: "PhotoMesh · page \(pageNumber)", attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.tertiaryLabel])
        let size = text.size()
        text.draw(at: CGPoint(x: page.width - margin - size.width, y: page.height - margin + 4))
    }

    /// Starts a new page unless at least `minimumHeight` is left.
    func keepTogether(minimumHeight: CGFloat) {
        if y + minimumHeight > bottom { beginPage() }
    }

    func rule() {
        keepTogether(minimumHeight: 12)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y + 2))
        path.addLine(to: CGPoint(x: page.width - margin, y: y + 2))
        UIColor.separator.setStroke()
        path.lineWidth = 0.6
        path.stroke()
        y += 12
    }

    func text(_ string: String, font: UIFont, color: UIColor, spacingAfter: CGFloat, indent: CGFloat = 0) {
        guard !string.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.5
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        let width = contentWidth - indent
        let height = ceil(attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        if y + height > bottom {
            beginPage()
        }
        attributed.draw(with: CGRect(x: margin + indent, y: y, width: width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += height + spacingAfter
    }

    /// One equation line, typeset when its LaTeX parses, plain otherwise.
    func math(_ line: String, indent: CGFloat) {
        let latex = EquationLaTeX.latex(for: line)
        guard MathText.parses(latex) else {
            text(line, font: .monospacedSystemFont(ofSize: 10.5, weight: .regular), color: .label, spacingAfter: 3, indent: indent)
            return
        }
        let label = MTMathUILabel()
        label.labelMode = .display
        label.textColor = .label
        label.backgroundColor = .clear
        label.latex = latex
        let width = contentWidth - indent
        var fontSize: CGFloat = 11.5
        var size = CGSize.zero
        repeat {
            label.fontSize = fontSize
            size = label.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
            if size.width <= width || fontSize <= 7 { break }
            fontSize -= 0.5
        } while true
        guard size.width > 0, size.height > 0 else {
            text(line, font: .monospacedSystemFont(ofSize: 10.5, weight: .regular), color: .label, spacingAfter: 3, indent: indent)
            return
        }
        let height = ceil(size.height) + 2
        if y + height > bottom { beginPage() }
        label.frame = CGRect(origin: .zero, size: CGSize(width: ceil(size.width), height: ceil(size.height)))
        label.layoutIfNeeded()
        let cg = context.cgContext
        cg.saveGState()
        cg.translateBy(x: margin + indent, y: y)
        label.layer.render(in: cg)
        cg.restoreGState()
        y += height + 3
    }

    func image(_ image: UIImage, maxHeight: CGFloat, spacingAfter: CGFloat) {
        let scale = min(contentWidth / image.size.width, maxHeight / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        if y + size.height > bottom { beginPage() }
        let rect = CGRect(x: margin + (contentWidth - size.width) / 2, y: y, width: size.width, height: size.height)
        image.draw(in: rect)
        UIColor.separator.setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        border.lineWidth = 0.6
        border.stroke()
        y += size.height + spacingAfter
    }
}
