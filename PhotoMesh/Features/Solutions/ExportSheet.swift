import SwiftUI
import UIKit

/// What can be taken out of the app: an LTspice schematic with its netlist, or a PDF of a
/// walkthrough. Files are written to a temporary folder and handed to the share sheet.
struct ExportSheet: View {
    enum Kind {
        case ltspice(analysis: CircuitAnalysis)
        case stepsPDF(analysis: CircuitAnalysis, solution: MethodSolution)
    }

    let kind: Kind
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var preview = ""
    @State private var failure: String?
    @State private var rendering = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundStyle(PMTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if rendering {
                        HStack(spacing: 10) {
                            ProgressView().tint(PMTheme.accent)
                            Text("Preparing…").font(.system(size: 14)).foregroundStyle(PMTheme.secondaryText)
                        }
                    } else if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(PMTheme.whyOrange)
                    } else {
                        ForEach(files, id: \.self) { url in
                            HStack {
                                Image(systemName: url.pathExtension == "pdf" ? "doc.richtext" : "doc.text")
                                    .foregroundStyle(PMTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(PMTheme.ink)
                                    Text(sizeText(url))
                                        .font(.system(size: 12))
                                        .foregroundStyle(PMTheme.secondaryText)
                                }
                                Spacer()
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(PMTheme.accent)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PMTheme.groupedBackground))
                        }
                        if files.count > 1 {
                            ShareLink(items: files) {
                                Label("Share all", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PMPrimaryButtonStyle(fillsWidth: true))
                        } else if let file = files.first {
                            ShareLink(item: file) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PMPrimaryButtonStyle(fillsWidth: true))
                        }
                        if !preview.isEmpty {
                            Text("NETLIST")
                                .font(.system(size: 11, weight: .semibold))
                                .kerning(0.6)
                                .foregroundStyle(PMTheme.secondaryText)
                                .padding(.top, 6)
                            Text(preview)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(PMTheme.ink)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(PMTheme.groupedBackground))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(PMTheme.accent)
                }
            }
        }
        .task { await prepare() }
    }

    private var title: String {
        switch kind {
        case .ltspice: return "Export to LTspice"
        case .stepsPDF: return "Export as PDF"
        }
    }

    private var description: String {
        switch kind {
        case .ltspice:
            return "Open the .asc in LTspice to see the same circuit drawn on its canvas, ready to run. The .cir netlist works in any SPICE. Element names get the letter SPICE expects (a battery becomes VB1, a lamp RLP1)."
        case .stepsPDF:
            return "Every step of this walkthrough, typeset with the circuit drawing on the first page, ready to print or hand in."
        }
    }

    private func sizeText(_ url: URL) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @MainActor
    private func prepare() async {
        rendering = true
        do {
            switch kind {
            case .ltspice(let analysis):
                let written = try CircuitExports.ltspiceFiles(for: analysis)
                files = written.urls
                preview = written.netlist
                Analytics.shared.track("export", ["kind": .string("ltspice")])
            case .stepsPDF(let analysis, let solution):
                let url = try StepsPDFExporter.export(analysis: analysis, solution: solution)
                files = [url]
                Analytics.shared.track("export", ["kind": .string("pdf")])
            }
        } catch {
            failure = error.localizedDescription
        }
        rendering = false
    }
}

/// Writes export files to a per-launch temporary folder.
enum CircuitExports {
    struct LTspiceFiles {
        var urls: [URL]
        var netlist: String
    }

    static var folder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoMesh Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func ltspiceFiles(for analysis: CircuitAnalysis) throws -> LTspiceFiles {
        guard let circuit = analysis.drawn ?? analysis.circuit else {
            throw NSError(domain: "PhotoMesh", code: 1, userInfo: [NSLocalizedDescriptionKey: "There is no circuit to export."])
        }
        let layout = SchematicLayoutEngine.layout(for: circuit)
        let files = SpiceExport.files(for: circuit, layout: layout, title: analysis.question)
        let base = folder.appendingPathComponent(files.baseName)
        let asc = base.appendingPathExtension("asc")
        let cir = base.appendingPathExtension("cir")
        try files.schematic.write(to: asc, atomically: true, encoding: .utf8)
        try files.netlist.write(to: cir, atomically: true, encoding: .utf8)
        return LTspiceFiles(urls: [asc, cir], netlist: files.netlist)
    }
}
