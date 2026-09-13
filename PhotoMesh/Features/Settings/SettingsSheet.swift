import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.resistorStyle) private var resistorStyle: ResistorStyle = .ansi
    @AppStorage(SettingsKeys.decimalSign) private var decimalSign: DecimalSign = .point
    @AppStorage(SettingsKeys.unitNotation) private var unitNotation: UnitNotation = .engineering
    @AppStorage(SettingsKeys.currentConvention) private var currentConvention: CurrentConvention = .conventional
    @AppStorage(SettingsKeys.useSampleCircuit) private var useSampleCircuit = false
    @AppStorage(SettingsKeys.confirmRecognized) private var confirmRecognized = true
    @AppStorage(SettingsKeys.fastRecognition) private var fastRecognition = false

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
                            Text("Model").foregroundStyle(PMTheme.ink)
                            Spacer()
                            Text(APIConfiguration.model)
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
                            Text("Fast recognition").foregroundStyle(PMTheme.ink)
                            Text("Less thinking: about 3× quicker, a bit less careful on messy photos")
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

    private let suggestions = [
        "google/gemini-3.6-flash",
        "google/gemini-3.5-flash-lite",
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
                Text("MODEL ID")
            } footer: {
                Text("Any OpenRouter model with image input works. Leave empty for the default.")
            }
            Section("SUGGESTIONS") {
                ForEach(suggestions, id: \.self) { candidate in
                    Button {
                        model = candidate == APIConfiguration.defaultModel ? "" : candidate
                    } label: {
                        HStack {
                            Text(candidate).font(.system(size: 15, design: .monospaced)).foregroundStyle(PMTheme.ink)
                            Spacer()
                            if APIConfiguration.model == candidate {
                                Image(systemName: "checkmark").foregroundStyle(PMTheme.accent)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
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
