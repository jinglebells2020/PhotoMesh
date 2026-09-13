import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.resistorStyle) private var resistorStyle: ResistorStyle = .ansi
    @AppStorage(SettingsKeys.decimalSign) private var decimalSign: DecimalSign = .point
    @AppStorage(SettingsKeys.unitNotation) private var unitNotation: UnitNotation = .engineering
    @AppStorage(SettingsKeys.currentConvention) private var currentConvention: CurrentConvention = .conventional

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
