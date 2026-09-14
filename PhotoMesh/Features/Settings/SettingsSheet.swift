import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.resistorStyle) private var resistorStyle: ResistorStyle = .ansi
    @AppStorage(SettingsKeys.decimalSign) private var decimalSign: DecimalSign = .point
    @AppStorage(SettingsKeys.unitNotation) private var unitNotation: UnitNotation = .engineering
    @AppStorage(SettingsKeys.currentConvention) private var currentConvention: CurrentConvention = .conventional
    @AppStorage(SettingsKeys.useSampleCircuit) private var useSampleCircuit = false
    @AppStorage(SettingsKeys.confirmRecognized) private var confirmRecognized = true
    @AppStorage(SettingsKeys.fastRecognition) private var fastRecognition = true
    @AppStorage(SettingsKeys.escalate) private var escalate = true
    @AppStorage("analytics.usage") private var shareUsage = false
    @AppStorage("analytics.scans") private var shareScans = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SettingsRow(title: "Resistor symbol", value: resistorStyle.title) {
                        OptionPickerView(title: "Resistor symbol", selection: $resistorStyle)
                    }
                    SettingsRow(title: "Decimal sign", value: decimalSign.title) {
                        OptionPickerView(title: "Decimal sign", selection: $decimalSign)
                    }
                    SettingsRow(title: "Unit notation", value: unitNotation.title) {
                        OptionPickerView(title: "Unit notation", selection: $unitNotation)
                    }
                    SettingsRow(title: "Current direction", value: currentConvention.title) {
                        OptionPickerView(title: "Current direction", selection: $currentConvention)
                    }
                } header: {
                    Text("CIRCUIT SETTINGS")
                } footer: {
                    Text("These settings affect how values are displayed and interpreted when scanned from schematics and handwriting.")
                }

                Section {
                    NavigationLink {
                        APIKeyView()
                    } label: {
                        HStack {
                            Text("OpenRouter API key").foregroundStyle(PMTheme.ink)
                            Spacer()
                            Text(APIConfiguration.apiKey == nil ? "Not set" : (APIConfiguration.isEnvironmentKey ? "From Xcode" : "Set"))
                                .font(.system(size: 15))
                                .foregroundStyle(APIConfiguration.apiKey == nil ? PMTheme.whyOrange : PMTheme.secondaryText)
                        }
                    }
                    NavigationLink {
                        ModelView()
                    } label: {
                        HStack {
                            Text("Models").foregroundStyle(PMTheme.ink)
                            Spacer()
                            Text(APIConfiguration.model.split(separator: "/").last.map(String.init) ?? APIConfiguration.model)
                                .font(.system(size: 15))
                                .foregroundStyle(PMTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Toggle(isOn: $confirmRecognized) {
                        Text("Check circuit before solving").foregroundStyle(PMTheme.ink)
                    }
                    .tint(PMTheme.accent)
                    Toggle(isOn: $fastRecognition) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fast first pass").foregroundStyle(PMTheme.ink)
                            Text("Low reasoning effort on the first read; about 3× quicker")
                                .font(.system(size: 12))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                    }
                    .tint(PMTheme.accent)
                    Toggle(isOn: $escalate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Escalate when unsure").foregroundStyle(PMTheme.ink)
                            Text("Re-read with the stronger model if the first result does not validate")
                                .font(.system(size: 12))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                    }
                    .tint(PMTheme.accent)
                    Toggle(isOn: $useSampleCircuit) {
                        Text("Use sample circuit").foregroundStyle(PMTheme.ink)
                    }
                    .tint(PMTheme.accent)
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Text("Diagnostics").foregroundStyle(PMTheme.ink)
                    }
                } header: {
                    Text("RECOGNITION")
                } footer: {
                    Text("Photos are sent to the selected model through OpenRouter to read the schematic. The key is stored in this device's Keychain. Sample mode skips the camera reader and solves a built-in circuit.")
                }

                Section {
                    Toggle(isOn: $shareUsage) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share anonymous usage").foregroundStyle(PMTheme.ink)
                            Text("Which features are used, how long recognition takes, when it fails")
                                .font(.system(size: 12))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                    }
                    .tint(PMTheme.accent)
                    Toggle(isOn: $shareScans) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share scans to improve recognition").foregroundStyle(PMTheme.ink)
                            Text("Your circuit pictures with the recognized and corrected netlists")
                                .font(.system(size: 12))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                    }
                    .tint(PMTheme.accent)
                    .onChange(of: shareScans) { _, on in if on { shareUsage = true } }
                    NavigationLink {
                        DataView()
                    } label: {
                        Text("Collected data").foregroundStyle(PMTheme.ink)
                    }
                } header: {
                    Text("PRIVACY & DATA")
                } footer: {
                    Text("Nothing is shared until you turn these on. There is no account; a random install id groups your data. Feedback you send from a walkthrough is kept with it.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PMTheme.accent)
                }
            }
        }
    }
}

private struct SettingsRow<Destination: View>: View {
    let title: String
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(PMTheme.ink)
                Spacer()
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(PMTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// Check-mark list for any `SettingsOption` enum.
struct OptionPickerView<Option: SettingsOption>: View {
    let title: String
    @Binding var selection: Option

    var body: some View {
        List {
            ForEach(Array(Option.allCases)) { option in
                Button {
                    Haptics.selection()
                    selection = option
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .foregroundStyle(PMTheme.ink)
                            if let subtitle = option.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(PMTheme.secondaryText)
                            }
                        }
                        Spacer()
                        if option == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(PMTheme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsSheet()
}

// MARK: - Recognition settings

private struct APIKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = APIConfiguration.isEnvironmentKey ? "" : (APIConfiguration.apiKey ?? "")
    @State private var saved = false

    var body: some View {
        List {
            Section {
                SecureField("sk-or-v1-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))
                    .onSubmit(save)
                if !key.isEmpty {
                    Button("Remove key", role: .destructive) {
                        key = ""
                        save()
                    }
                }
            } header: {
                Text("OPENROUTER API KEY")
            } footer: {
                Text(APIConfiguration.isEnvironmentKey
                     ? "A key from the OPENROUTER_API_KEY environment variable is currently in use; it overrides anything entered here."
                     : "Create a key at openrouter.ai → Keys. It is stored in the Keychain and only sent to openrouter.ai.")
            }
            Section {
                Button(saved ? "Saved" : "Save") { save() }
                    .disabled(saved)
                    .foregroundStyle(saved ? PMTheme.secondaryText : PMTheme.accent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("API key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        APIConfiguration.saveAPIKey(key)
        Haptics.notify(.success)
        withAnimation { saved = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            saved = false
        }
    }
}

private struct ModelView: View {
    @AppStorage(SettingsKeys.openRouterModel) private var model = ""
    @AppStorage(SettingsKeys.fallbackModel) private var fallbackModel = ""

    private let suggestions = [
        "google/gemini-3.5-flash-lite",
        "google/gemini-3.6-flash",
        "openai/gpt-5-nano",
        "google/gemini-2.5-flash",
    ]

    var body: some View {
        List {
            Section {
                TextField(APIConfiguration.defaultModel, text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))
            } header: {
                Text("FIRST PASS")
            } footer: {
                Text("Reads every scan. Measured on the test set: gemini-3.5-flash-lite with the fast first pass is as accurate as gemini-3.6-flash at a quarter of the cost and 2–3 s per scan. Leave empty for the default.")
            }
            Section {
                TextField(APIConfiguration.defaultFallbackModel, text: $fallbackModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))
            } header: {
                Text("SECOND PASS")
            } footer: {
                Text("Used only when the first read fails validation, finds no circuit, or the two solving methods disagree.")
            }
            Section("SUGGESTIONS") {
                ForEach(suggestions, id: \.self) { candidate in
                    HStack {
                        Text(candidate).font(.system(size: 14, design: .monospaced)).foregroundStyle(PMTheme.ink)
                        Spacer()
                        Button("1st") { model = candidate == APIConfiguration.defaultModel ? "" : candidate }
                            .buttonStyle(.bordered)
                            .tint(APIConfiguration.model == candidate ? PMTheme.accent : .gray)
                        Button("2nd") { fallbackModel = candidate == APIConfiguration.defaultFallbackModel ? "" : candidate }
                            .buttonStyle(.bordered)
                            .tint(APIConfiguration.fallbackModel == candidate ? PMTheme.accent : .gray)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What has been collected on this device, with export, upload settings and deletion.
private struct DataView: View {
    @AppStorage(SettingsKeys.analyticsEndpoint) private var endpoint = ""
    @AppStorage(SettingsKeys.analyticsEndpointKey) private var endpointKey = ""
    @State private var summary = Analytics.shared.summary()
    @State private var exportURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                row("Usage events", "\(summary.events)")
                row("Scan samples", "\(summary.samples)")
                row("Size", ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file))
                row("Install id", String(Analytics.installId.prefix(8)) + "…")
            } header: {
                Text("ON THIS DEVICE")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share export file", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        exportURL = Analytics.shared.exportFile()
                    } label: {
                        Label("Prepare export", systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(summary.events == 0 && summary.samples == 0)
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete collected data", systemImage: "trash")
                }
                .disabled(summary.events == 0 && summary.samples == 0)
            } header: {
                Text("EXPORT")
            } footer: {
                Text("One JSON file with every event and sample (pictures included as base64).")
            }

            Section {
                TextField("https://…workers.dev", text: $endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                SecureField("Ingest key", text: $endpointKey)
                    .font(.system(size: 14, design: .monospaced))
                Button("Upload now") {
                    Analytics.shared.flush()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        summary = Analytics.shared.summary()
                    }
                }
                .disabled(Analytics.endpoint == nil || (summary.events == 0 && summary.samples == 0))
            } header: {
                Text("UPLOAD ENDPOINT (DEVELOPER)")
            } footer: {
                Text("HTTPS URL that accepts a JSON POST; see tools/telemetry-worker in the repository for a ready-made collector. Pending data uploads on launch and after each solve.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Collected data")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { summary = Analytics.shared.summary() }
        .confirmationDialog("Delete all collected data on this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Analytics.shared.deleteAll()
                exportURL = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    summary = Analytics.shared.summary()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(PMTheme.ink)
            Spacer()
            Text(value).foregroundStyle(PMTheme.secondaryText).font(.system(size: 15, design: .rounded))
        }
    }
}

private struct DiagnosticsView: View {
    @State private var text = RecognitionLog.shared.text
    @State private var copied = false

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No recognition requests yet. Scan a circuit, then come back here to see what happened." : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PMTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(PMTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(text.isEmpty)
                    Button {
                        RecognitionLog.shared.clear()
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(text.isEmpty)
                }
                .foregroundStyle(PMTheme.accent)
            }
        }
        .onAppear { text = RecognitionLog.shared.text }
    }
}
