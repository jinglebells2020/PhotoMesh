import SwiftUI

/// Every circuit solved so far. Tapping one re-runs the engine and opens its solutions.
struct HistorySheet: View {
    /// Free keeps this many of the newest circuits open; the rest are Plus.
    static let freeCount = 3

    @Environment(\.dismiss) private var dismiss
    @State private var store = HistoryStore.shared
    @State private var selected: HistoryEntry?
    @State private var confirmClear = false
    @State private var presentingPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("No circuits yet", systemImage: "clock.arrow.circlepath", description: Text("Circuits you scan or draw will be kept here."))
                } else {
                    let hasPlus = PlusAccess.allows(.history)
                    List {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                            let locked = index >= HistorySheet.freeCount && !hasPlus
                            Button {
                                if locked {
                                    PlusAccess.notedLockedTap(.history)
                                    presentingPaywall = true
                                } else {
                                    selected = entry
                                }
                            } label: {
                                HistoryRow(entry: entry, locked: locked)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                        .onDelete { offsets in store.remove(atOffsets: offsets) }
                        if !hasPlus, store.entries.count > HistorySheet.freeCount {
                            PlusLockCard(feature: .history, compact: true)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.entries.isEmpty {
                        Button("Clear", role: .destructive) { confirmClear = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PMTheme.accent)
                }
            }
            .confirmationDialog("Remove all saved circuits?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(item: $selected) { entry in
            SolutionsSheet(request: SolutionRequest(source: .circuit(entry.circuit)))
                .presentationBackground(PMTheme.darkSheet)
        }
        .sheet(isPresented: $presentingPaywall) {
            PlusSheet()
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    var locked = false

    private var layout: SchematicLayout { SchematicLayoutEngine.layout(for: entry.circuit) }

    var body: some View {
        HStack(spacing: 14) {
            StaticSchematic(layout: layout)
                .frame(width: 96, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.question)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
                    .lineLimit(2)
                Text(entry.headline)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(PMTheme.accent)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: entry.origin == .scan ? "camera" : "scribble")
                        .font(.system(size: 11))
                    Text(entry.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(size: 12))
                }
                .foregroundStyle(PMTheme.secondaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(locked ? PMTheme.plusOrange : PMTheme.tertiaryText)
        }
        .opacity(locked ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

#Preview {
    HistorySheet()
}
