import SwiftUI

/// Collects each key's frame so the alternates bubble can be placed above the pressed key.
struct KeyFramePreference: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Photomath-style keyboard: a tool row, four category chips, and a key grid.
struct CalculatorKeyboardView: View {
    @Binding var tab: CalcTab
    @Binding var isAlpha: Bool
    var isInteractive = true
    let onAction: (KeyAction) -> Void

    @State private var alternatesKey: CalcKey?

    private let keyHeight: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            categoryRow
            keyGrid
        }
        .background(PMTheme.keyboardBackground)
        .overlayPreferenceValue(KeyFramePreference.self) { frames in
            alternatesOverlay(frames)
        }
    }

    // MARK: Rows

    private var toolbarRow: some View {
        HStack(spacing: 0) {
            ToolbarKey(isActive: isAlpha, label: "Letters", action: { onAction(.toggleAlpha) }) {
                Text("abc").font(.system(size: 17))
            }
            ToolbarKey(label: "History", action: { onAction(.history) }) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 18, weight: .medium))
            }
            ToolbarKey(label: "Move cursor left", action: { onAction(.moveLeft) }) {
                Image(systemName: "arrow.left").font(.system(size: 18, weight: .medium))
            }
            ToolbarKey(label: "Move cursor right", action: { onAction(.moveRight) }) {
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .medium))
            }
            ToolbarKey(label: "Solve", action: { onAction(.enter) }) {
                Image(systemName: "return").font(.system(size: 18, weight: .medium))
            }
            ToolbarKey(label: "Delete", action: { onAction(.backspace) }) {
                Image(systemName: "delete.left").font(.system(size: 18, weight: .medium))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .allowsHitTesting(isInteractive)
    }

    private var categoryRow: some View {
        HStack(spacing: 8) {
            ForEach(CalcTab.allCases) { candidate in
                CategoryChip(tab: candidate, isSelected: !isAlpha && tab == candidate) {
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.15)) {
                        isAlpha = false
                        tab = candidate
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .allowsHitTesting(isInteractive)
    }

    private var keyGrid: some View {
        let rows = isAlpha ? KeyboardLayouts.alpha : KeyboardLayouts.rows(for: tab)
        return VStack(spacing: 0.5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0.5) {
                    ForEach(row) { key in
                        KeyView(key: key, height: keyHeight, isInteractive: isInteractive) {
                            onAction(key.action)
                        } onLongPress: {
                            alternatesKey = key
                        }
                    }
                }
            }
        }
        .background(PMTheme.keySeparator)
        .padding(.bottom, 4)
    }

    // MARK: Alternates

    @ViewBuilder
    private func alternatesOverlay(_ frames: [String: Anchor<CGRect>]) -> some View {
        if let key = alternatesKey, let anchor = frames[key.id] {
            GeometryReader { proxy in
                let frame = proxy[anchor]
                let optionWidth: CGFloat = 52
                let bubbleWidth = optionWidth * CGFloat(key.alternates.count) + 8
                let x = min(max(frame.midX - bubbleWidth / 2, 4), proxy.size.width - bubbleWidth - 4)
                let y = frame.minY - 66

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { alternatesKey = nil }

                    AlternatesBubble(keys: key.alternates, optionWidth: optionWidth) { action in
                        Haptics.impact(.light)
                        onAction(action)
                        alternatesKey = nil
                    }
                    .frame(width: bubbleWidth, height: 60)
                    .offset(x: x, y: y)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Pieces

private struct ToolbarKey<Label: View>: View {
    var isActive = false
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Label

    init(isActive: Bool = false, label: String, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Label) {
        self.isActive = isActive
        self.label = label
        self.action = action
        self.content = content
    }

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            content()
                .foregroundStyle(PMTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? PMTheme.toolbarChipActive : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct CategoryChip: View {
    let tab: CalcTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(tab.topLine)
                Text(tab.bottomLine)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isSelected ? .white : PMTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                Capsule().fill(isSelected ? Color.black : Color.white)
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : PMTheme.chipBorder, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Reports the button's pressed state back through a binding.
struct PressReportingButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

private struct KeyView: View {
    let key: CalcKey
    let height: CGFloat
    var isInteractive = true
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false
    @State private var longPressFired = false

    private var showsBubble: Bool {
        if case .text = key.label { return true }
        return false
    }

    var body: some View {
        if key.isEmpty {
            Color.white
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            Button {
                if longPressFired { return }
                Haptics.impact(.light)
                onTap()
            } label: {
                KeyLabelView(label: key.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay(alignment: .bottomTrailing) {
                        if !key.alternates.isEmpty {
                            Circle()
                                .fill(PMTheme.accent)
                                .frame(width: 4, height: 4)
                                .padding(6)
                        }
                    }
                    .background(isPressed ? PMTheme.keyPressed : PMTheme.keyBackground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressReportingButtonStyle(isPressed: $isPressed))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        guard !key.alternates.isEmpty else { return }
                        longPressFired = true
                        Haptics.impact(.medium)
                        onLongPress()
                    }
            )
            .onChange(of: isPressed) { _, pressed in
                guard !pressed, longPressFired else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    longPressFired = false
                }
            }
            .overlay(alignment: .top) {
                if isPressed && showsBubble {
                    KeyBubble(label: key.label)
                        .offset(y: -60)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isPressed ? 1 : 0)
            .anchorPreference(key: KeyFramePreference.self, value: .bounds) { [key.id: $0] }
            .allowsHitTesting(isInteractive)
            .accessibilityLabel(key.accessibilityLabel)
        }
    }
}

/// The enlarged label that pops up above a pressed key, like the system keyboard.
private struct KeyBubble: View {
    let label: KeyLabel

    var body: some View {
        KeyLabelView(label: label, scale: 1.35)
            .frame(width: 62, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            )
    }
}

private struct AlternatesBubble: View {
    let keys: [CalcKey]
    let optionWidth: CGFloat
    let onSelect: (KeyAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys) { key in
                Button {
                    onSelect(key.action)
                } label: {
                    KeyLabelView(label: key.label)
                        .frame(width: optionWidth, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
    }
}

#Preview {
    VStack {
        Spacer()
        CalculatorKeyboardView(tab: .constant(.basic), isAlpha: .constant(false)) { _ in }
    }
}
