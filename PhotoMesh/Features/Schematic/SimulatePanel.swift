import SwiftUI
import Charts

/// Plays the circuit in time: transport controls, a scrubber, plots of the chosen quantities
/// with a cursor at the playhead, and the switches to flip while it runs.
struct SimulatePanel: View {
    @Bindable var model: ExplorerModel

    private var formatter: QuantityFormatter { FormattingPreferences.formatter() }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if let error = model.simulationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.whyOrange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let simulation = model.simulation {
                    transport(simulation)
                    scrubber(simulation)
                    readouts(simulation)
                    charts(simulation)
                    traceChips
                    if !model.switches.isEmpty { switchControls }
                    notes(simulation)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(PMTheme.accent)
                        Text("Simulating…")
                            .font(.system(size: 14))
                            .foregroundStyle(PMTheme.secondaryText)
                    }
                    .padding(.vertical, 20)
                }
            }
            .padding(16)
        }
        .onAppear { if model.simulation == nil { model.simulate() } }
        .onDisappear { model.pause() }
    }

    // MARK: Transport

    private func transport(_ simulation: TransientSimulator.Result) -> some View {
        HStack(spacing: 14) {
            Button {
                Haptics.impact(.light)
                model.togglePlay()
            } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(PMTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.playing ? "Pause" : "Play")

            Button {
                Haptics.impact(.light)
                model.restart()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(PMTheme.groupedBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restart")

            VStack(alignment: .leading, spacing: 2) {
                Text("t = \(formatter.format(model.time, "s"))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PMTheme.ink)
                    .monospacedDigit()
                Text("of \(formatter.format(simulation.duration, "s")) after switch-on")
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            Spacer()
            Menu {
                Picker("Speed", selection: $model.playbackSeconds) {
                    Text("Slow").tag(12.0)
                    Text("Normal").tag(6.0)
                    Text("Fast").tag(3.0)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                    Text(model.playbackSeconds >= 12 ? "Slow" : (model.playbackSeconds <= 3 ? "Fast" : "Normal"))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PMTheme.accent)
            }
        }
    }

    private func scrubber(_ simulation: TransientSimulator.Result) -> some View {
        Slider(
            value: Binding(
                get: { model.time },
                set: { newValue in
                    model.pause()
                    model.time = min(max(newValue, 0), simulation.duration)
                }
            ),
            in: 0...max(simulation.duration, 1e-9)
        )
        .tint(PMTheme.accent)
    }

    // MARK: Values at the playhead

    private func readouts(_ simulation: TransientSimulator.Result) -> some View {
        let index = simulation.index(at: model.time)
        let keys = orderedSelectedTraces
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keys) { key in
                    let trace = model.trace(key)
                    let value = index < trace.count ? trace[index] : 0
                    HStack(spacing: 6) {
                        Circle().fill(color(for: key)).frame(width: 8, height: 8)
                        Text("\(key.label) = \(formatter.format(value, key.isCurrent ? "A" : "V"))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PMTheme.ink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(PMTheme.groupedBackground))
                }
            }
        }
    }

    // MARK: Charts

    private struct Point: Identifiable {
        let id: Int
        let t: Double
        let v: Double
    }

    private struct Series: Identifiable {
        let id: String
        let label: String
        let color: Color
        let points: [Point]
    }

    private var orderedSelectedTraces: [ExplorerModel.TraceKey] {
        model.availableTraces.filter { model.selectedTraces.contains($0) }
    }

    private func series(for keys: [ExplorerModel.TraceKey], simulation: TransientSimulator.Result) -> [Series] {
        keys.map { key in
            let trace = model.trace(key)
            let step = max(1, trace.count / 180)
            var points: [Point] = []
            var i = 0
            while i < trace.count {
                points.append(Point(id: i, t: simulation.times[i], v: trace[i]))
                i += step
            }
            if let last = trace.indices.last, points.last?.id != last { points.append(Point(id: last, t: simulation.times[last], v: trace[last])) }
            return Series(id: key.id, label: key.label, color: color(for: key), points: points)
        }
    }

    @ViewBuilder
    private func charts(_ simulation: TransientSimulator.Result) -> some View {
        let voltages = orderedSelectedTraces.filter { !$0.isCurrent }
        let currents = orderedSelectedTraces.filter { $0.isCurrent }
        if !voltages.isEmpty {
            chart(series(for: voltages, simulation: simulation), unit: "V", duration: simulation.duration)
        }
        if !currents.isEmpty {
            chart(series(for: currents, simulation: simulation), unit: "A", duration: simulation.duration)
        }
        if voltages.isEmpty, currents.isEmpty {
            Text("Choose what to plot below.")
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.secondaryText)
        }
    }

    private func chart(_ series: [Series], unit: String, duration: Double) -> some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { p in
                    LineMark(x: .value("Time", p.t), y: .value("Value", p.v))
                }
                .foregroundStyle(s.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }
            RuleMark(x: .value("Now", model.time))
                .foregroundStyle(PMTheme.ink.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: 0...max(duration, 1e-9))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text(formatter.format(t, "s")).font(.system(size: 10))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatter.format(v, unit)).font(.system(size: 10))
                    }
                }
            }
        }
        .frame(height: 150)
        .padding(.top, 4)
    }

    // MARK: Trace choice

    private var traceChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLOT")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.availableTraces) { key in
                        let on = model.selectedTraces.contains(key)
                        Button {
                            Haptics.selection()
                            if on { model.selectedTraces.remove(key) } else { model.selectedTraces.insert(key) }
                        } label: {
                            Text(key.label)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(on ? .white : PMTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(on ? color(for: key) : PMTheme.groupedBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private static let palette: [Color] = [
        PMTheme.accent, Color(red: 0.86, green: 0.36, blue: 0.14), Color(red: 0.16, green: 0.42, blue: 0.86),
        Color(red: 0.55, green: 0.24, blue: 0.75), Color(red: 0.0, green: 0.55, blue: 0.6), Color(red: 0.72, green: 0.16, blue: 0.4),
    ]

    private func color(for key: ExplorerModel.TraceKey) -> Color {
        let index = model.availableTraces.firstIndex(of: key) ?? 0
        return SimulatePanel.palette[index % SimulatePanel.palette.count]
    }

    // MARK: Switches

    private var switchControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SWITCHES")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            HStack(spacing: 8) {
                ForEach(model.switches) { component in
                    let closed = model.isClosedInSimulation(component.id)
                    Button {
                        Haptics.impact(.light)
                        model.toggleSwitch(component.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: closed ? "switch.2" : "switch.2")
                            Text("\(component.id): \(closed ? "close → open" : "open → close") now")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PMTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().stroke(PMTheme.accent, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
                if !model.switchEvents.isEmpty {
                    Button("Clear flips") { model.clearEvents() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PMTheme.secondaryText)
                }
            }
            if !model.switchEvents.isEmpty {
                Text(model.switchEvents.sorted { $0.time < $1.time }.map { "\($0.elementId) at \(formatter.format($0.time, "s"))" }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.secondaryText)
            }
        }
    }

    // MARK: Notes

    @ViewBuilder
    private func notes(_ simulation: TransientSimulator.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !simulation.timeConstants.isEmpty {
                Text(simulation.timeConstants.sorted { $0.key < $1.key }.map { "τ(\($0.key)) = \(formatter.format($0.value, "s"))" }.joined(separator: " · "))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(PMTheme.secondaryText)
                Text("A capacitor's voltage or an inductor's current covers 63% of its remaining change in every time constant; after five it has settled. The dots slow down as the currents die away.")
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.hasEnergyStorage {
                Text("Nothing here stores energy, so every current settles the instant the circuit is switched on: the curves are flat. Add a capacitor or a coil to watch charging and decay.")
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !simulation.missingValues.isEmpty {
                Text("\(simulation.missingValues.joined(separator: ", ")) \(simulation.missingValues.count == 1 ? "has" : "have") no value: set one in Tweak to see \(simulation.missingValues.count == 1 ? "it" : "them") charge.")
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.whyOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
