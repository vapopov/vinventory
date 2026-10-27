import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PurchaseExportButton: View {
    var store: InventoryStore
    var project: String? = nil

    var body: some View {
        Button { export(project: project) } label: { icon }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.yellow)
        .help("Export purchases as CSV")
        .accessibilityLabel("Export purchases as CSV")
    }

    private var icon: some View { Image(systemName: "arrow.up.to.line").frame(width: 26, height: 26) }

    private func export(project: String? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = project.map { $0 + "-purchase.csv" } ?? "purchase.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.perform { try PurchaseCSV.encode(store.purchases, project: project).write(to: url, atomically: true, encoding: .utf8) }
    }
}
