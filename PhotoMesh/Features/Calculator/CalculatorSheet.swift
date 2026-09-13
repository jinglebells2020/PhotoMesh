import SwiftUI

/// Manual entry. Mirrors Photomath's calculator sheet: title bar, dotted input line,
/// live result with a green bar, "Show Solution" pill, custom keyboard.
struct CalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.decimalSign) private var decimalSign: DecimalSign = .point
    @AppStorage(SettingsKeys.calculatorHistory) private var historyJSON = "[]"

    @State private var text = ""
    @State private var cursor = 0
    @State private var tab: CalcTab = .basic
    @State private var isAlpha = false
    @State private var showHistory = false
    @State private var solutionRequest: SolutionRequest?
    @State private var mode: EntryMode = .keyboard

    private enum EntryMode: Hashable {
        case keyboard, draw
    }

    private enum Evaluation {
        case empty
        case value(String)
        case incomplete
        case unsupported
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker

            if mode == .draw {
                SketchCanvasView { circuit in
                    solutionRequest = SolutionRequest(source: .circuit(circuit))
                }
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            inputField
                            resultArea
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)

                    if showsSolutionButton {
                        Button(action: showSolution) {
                            HStack(spacing: 10) {
                                Text("Show Solution")
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .buttonStyle(PMPrimaryButtonStyle())
                        .padding(.bottom, 26)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showsSolutionButton)

                CalculatorKeyboardView(tab: $tab, isAlpha: $isAlpha, onAction: handle)
            }
        }
        .background((mode == .draw ? Color.white : PMTheme.keyboardBackground).ignoresSafeArea())
        // Drawing strokes must never turn into a swipe-to-dismiss; Close still works.
        .interactiveDismissDisabled(mode == .draw)
        .sheet(item: $solutionRequest) { request in
            SolutionsSheet(request: request)
                .presentationBackground(PMTheme.darkSheet)
        }
        .sheet(isPresented: $showHistory) {
            CalculatorHistorySheet(entries: history, onSelect: load(fromHistory:), onClear: clearHistory)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Sections

    private var modePicker: some View {
        Picker("Entry mode", selection: $mode) {
            Text("Keyboard").tag(EntryMode.keyboard)
            Text("Draw circuit").tag(EntryMode.draw)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var header: some View {
        ZStack {
            Text("Calculator")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PMTheme.ink)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .font(.system(size: 17))
                    .foregroundStyle(PMTheme.accent)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white)
    }

    private var inputField: some View {
        HStack(alignment: .center, spacing: 8) {
            if text.isEmpty {
                Text("Type a circuit problem...")
                    .font(.system(size: 17))
                    .foregroundStyle(PMTheme.secondaryText)
                    .overlay(alignment: .bottom) {
                        DottedLine().frame(height: 1).offset(y: 5)
                    }
            } else {
                ExpressionText(text: text, cursor: cursor)
            }
            Spacer(minLength: 0)
            if !text.isEmpty {
                Button {
                    Haptics.impact(.light)
                    text = ""
                    cursor = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(white: 0.62))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            if hasResult {
                DottedLine().frame(height: 1).padding(.horizontal, 8)
            }
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        switch evaluation {
        case .value(let result):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(PMTheme.accent)
                    .frame(width: 4)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("=")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(PMTheme.secondaryText)
                    Text(result)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(PMTheme.ink)
                        .textSelection(.enabled)
                }
                .padding(.leading, 12)
                .padding(.vertical, 18)
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        case .incomplete:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.accent)
                Text("Please enter a complete problem so we can solve it!")
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        case .empty, .unsupported:
            EmptyView()
        }
    }

    // MARK: Derived state

    private var evaluation: Evaluation {
        guard !text.isEmpty else { return .empty }
        let sign = Character(decimalSign.symbol)
        let evaluator = ExpressionEvaluator(decimalSign: sign)
        do {
            let value = try evaluator.evaluate(text)
            return .value(ExpressionEvaluator.format(value, decimalSign: sign))
        } catch ExpressionEvaluator.Failure.incomplete {
            return .incomplete
        } catch {
            return .unsupported
        }
    }

    private var hasResult: Bool {
        if case .value = evaluation { return true }
        return false
    }

    private var showsSolutionButton: Bool {
        switch evaluation {
        case .value, .unsupported: return true
        case .empty, .incomplete: return false
        }
    }

    private var history: [String] {
        guard let data = historyJSON.data(using: .utf8),
              let entries = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return entries
    }

    // MARK: Actions

    private func handle(_ action: KeyAction) {
        switch action {
        case .insert(let string, let cursorOffset):
            guard !string.isEmpty else { return }
            let position = text.index(text.startIndex, offsetBy: min(cursor, text.count))
            text.insert(contentsOf: string, at: position)
            cursor += cursorOffset ?? string.count
        case .backspace:
            guard cursor > 0 else { return }
            let position = text.index(text.startIndex, offsetBy: cursor - 1)
            text.remove(at: position)
            cursor -= 1
        case .moveLeft:
            cursor = max(0, cursor - 1)
        case .moveRight:
            cursor = min(text.count, cursor + 1)
        case .enter:
            if showsSolutionButton { showSolution() }
        case .toggleAlpha:
            withAnimation(.easeOut(duration: 0.15)) { isAlpha.toggle() }
        case .history:
            showHistory = true
        }
    }

    private func showSolution() {
        Haptics.impact(.medium)
        remember(text)
        solutionRequest = SolutionRequest(source: .expression(text))
    }

    private func remember(_ entry: String) {
        var entries = history.filter { $0 != entry }
        entries.insert(entry, at: 0)
        if entries.count > 30 { entries = Array(entries.prefix(30)) }
        if let data = try? JSONEncoder().encode(entries), let json = String(data: data, encoding: .utf8) {
            historyJSON = json
        }
    }

    private func load(fromHistory entry: String) {
        text = entry
        cursor = entry.count
        showHistory = false
    }

    private func clearHistory() {
        historyJSON = "[]"
    }
}

// MARK: - Input rendering

/// Expression text with a blinking caret at `cursor` and a dotted underline.
struct ExpressionText: View {
    let text: String
    let cursor: Int

    @State private var caretVisible = true

    var body: some View {
        let split = text.index(text.startIndex, offsetBy: min(max(cursor, 0), text.count))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 0) {
                Text(String(text[..<split]))
                Rectangle()
                    .fill(PMTheme.accent)
                    .frame(width: 2, height: 28)
                    .opacity(caretVisible ? 1 : 0)
                Text(String(text[split...]))
            }
            .font(.system(size: 24))
            .foregroundStyle(PMTheme.ink)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                DottedLine().frame(height: 1)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                caretVisible = false
            }
        }
    }
}

struct DottedLine: View {
    var color: Color = Color(white: 0.62)

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [2, 2.5]))
        }
    }
}

// MARK: - History

struct CalculatorHistorySheet: View {
    let entries: [String]
    let onSelect: (String) -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath", description: Text("Problems you solve will show up here."))
                } else {
                    List(entries, id: \.self) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            Text(entry)
                                .font(.system(size: 18))
                                .foregroundStyle(PMTheme.ink)
                                .lineLimit(1)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !entries.isEmpty {
                        Button("Clear", role: .destructive, action: onClear)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CalculatorSheet()
}
