import SwiftUI

/// Sliders for every value and a toggle for every switch. The schematic above re-solves as the
/// user drags, so the effect of a change is seen, not calculated.
struct TweakPanel: View {
    @Bindable var model: ExplorerModel

    private var formatter: QuantityFormatter { FormattingPreferences.formatter() }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if let comparison = model.answerComparison {
                    AnswerComparisonRow(label: comparison.label, original: comparison.original, tweaked: comparison.tweaked, changed: model.hasTweaks)
                }
                if let error = model.tweakError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.whyOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.baseCircuit.components) { component in
                    if component.kind.isSwitch {
                        SwitchRow(component: component, isClosed: model.isClosed(component.id)) {
                            Haptics.impact(.light)
                            model.toggleSwitch(component.id)
                        }
                    } else {
                        ValueSliderRow(
                            component: component,
                            value: model.value(of: component.id),
                            result: model.tweaked.methods.first?.elements.first { $0.id == component.id },
                            formatter: formatter
                        ) { newValue in
                            model.setValue(newValue, for: component.id)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        Haptics.impact(.light)
                        withAnimation { model.resetTweaks() }
                    } label: {
                        Label("Back to the drawing", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .disabled(!model.hasTweaks)
                    .opacity(model.hasTweaks ? 1 : 0.45)
                    .foregroundStyle(PMTheme.accent)
                    Spacer()
                }
                .padding(.top, 4)
                Text("Resistors, capacitors and inductors range over a hundredfold either way; sources from zero to double. Tap a switch on the drawing to flip it.")
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

/// "Current through R2: 1.538 A → 2.104 A".
private struct AnswerComparisonRow: View {
    let label: String
    let original: String
    let tweaked: String
    let changed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(PMTheme.secondaryText)
            HStack(spacing: 10) {
                Text(original)
                    .font(.system(size: 16, weight: changed ? .regular : .bold, design: .rounded))
                    .foregroundStyle(changed ? PMTheme.secondaryText : PMTheme.ink)
                    .strikethrough(changed, color: PMTheme.tertiaryText)
                if changed {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PMTheme.tertiaryText)
                    Text(tweaked)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PMTheme.accent)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PMTheme.groupedBackground))
        .animation(.easeOut(duration: 0.2), value: tweaked)
    }
}

private struct SwitchRow: View {
    let component: Component
    let isClosed: Bool
    let toggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.id)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PMTheme.ink)
                Text(isClosed ? "Closed: a plain wire" : "Open: no current can pass")
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isClosed }, set: { _ in toggle() }))
                .labelsHidden()
                .tint(PMTheme.accent)
        }
        .padding(.vertical, 4)
    }
}

/// One component: name, live value, what flows through it, and the slider.
private struct ValueSliderRow: View {
    let component: Component
    let value: Double
    let result: ElementResult?
    let formatter: QuantityFormatter
    let onChange: (Double) -> Void

    /// Where the slider sits for the current value (0…1).
    private var position: Double {
        let nominal = ValueSliderRow.nominal(component)
        if ValueSliderRow.isLogarithmic(component.kind) {
            guard value > 0 else { return 0 }
            return min(max(0.5 + log10(value / nominal) / 4, 0), 1)
        }
        return min(max(value / (2 * nominal), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(component.id)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PMTheme.ink)
                Text(component.kind.displayName.lowercased())
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.secondaryText)
                Spacer()
                Button {
                    onChange(component.value)
                } label: {
                    Text(component.kind.valueText(value, formatter: formatter))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(abs(value - component.value) > 1e-12 * max(1, abs(component.value)) ? PMTheme.accent : PMTheme.ink)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(component.id) to its drawn value")
            }
            Slider(value: Binding(get: { position }, set: { onChange(ValueSliderRow.value(at: $0, for: component)) }), in: 0...1)
                .tint(PMTheme.accent)
            if let result {
                Text(resultText(result))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(PMTheme.secondaryText)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.15), value: value)
    }

    private func resultText(_ result: ElementResult) -> String {
        switch component.kind.dcRole {
        case .voltageSource:
            let delivered = -result.current * result.voltage
            return "I = \(formatter.format(abs(result.current), "A")) · \(delivered >= 0 ? "delivers" : "absorbs") \(formatter.format(abs(delivered), "W"))"
        case .currentSource:
            return "V = \(formatter.format(abs(result.voltage), "V")) · \(result.power < 0 ? "delivers" : "absorbs") \(formatter.format(abs(result.power), "W"))"
        case .open:
            return "no current at DC · V = \(formatter.format(abs(result.voltage), "V"))"
        case .short:
            return "I = \(formatter.format(abs(result.current), "A")) · no voltage at DC"
        case .resistor:
            return "I = \(formatter.format(abs(result.current), "A")) · V = \(formatter.format(abs(result.voltage), "V")) · P = \(formatter.format(abs(result.power), "W"))"
        }
    }

    // MARK: Slider mapping

    static func isLogarithmic(_ kind: ComponentKind) -> Bool {
        switch kind {
        case .resistor, .lamp, .capacitor, .inductor: return true
        default: return false
        }
    }

    /// The value the slider is centred on: the drawn value, or a sensible one when none was given.
    static func nominal(_ component: Component) -> Double {
        if component.value > 0 { return component.value }
        switch component.kind {
        case .capacitor: return 100e-6
        case .inductor: return 10e-3
        case .resistor, .lamp: return 1000
        case .voltageSource, .battery: return 9
        case .currentSource: return 1
        default: return 1
        }
    }

    static func value(at position: Double, for component: Component) -> Double {
        let base = nominal(component)
        let p = min(max(position, 0), 1)
        if isLogarithmic(component.kind) {
            let raw = base * pow(10, (p - 0.5) * 4)
            return roundToNiceness(raw)
        }
        let raw = base * 2 * p
        return roundToNiceness(raw)
    }

    /// Three significant figures, so the readout never shows 4.6999999.
    static func roundToNiceness(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let exponent = floor(log10(x))
        let scale = pow(10, exponent - 2)
        return (x / scale).rounded() * scale
    }
}
