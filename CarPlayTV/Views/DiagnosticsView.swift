import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject private var diagnostics = Diagnostics.shared

    var body: some View {
        List {
            if diagnostics.entries.isEmpty {
                Text("Nothing recorded yet. Connect to CarPlay and play something, then come back here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(diagnostics.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: diagnostics.report) { Image(systemName: "square.and.arrow.up") }
                    .disabled(diagnostics.entries.isEmpty)
                Button("Clear", role: .destructive) { diagnostics.clear() }
                    .disabled(diagnostics.entries.isEmpty)
            }
        }
    }
}
