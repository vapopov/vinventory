import SwiftUI

struct ProjectRequestsView: View {
    var store: InventoryStore
    var project: String
    var query: String
    private var entries: [ProjectBOMEntry] {
        store.bomEntries(for: project).filter { entry in
            store.requestedQuantity(entry) > 0 && (query.isEmpty || [entry.item.designators, entry.item.value, entry.item.package, entry.item.lcsc].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    @State private var page = 0
    @State private var pageSize = 25

    var body: some View {
        let filtered = entries
        let offset = min(page * pageSize, filtered.count)
        let visible = filtered.dropFirst(offset).prefix(pageSize)
        VStack(spacing: 0) {
            ProjectRequestsTable(rows: visible.enumerated().map { index, entry in
                ProjectRequestRow(id: entry.id, values: [String(offset + index + 1), entry.item.designators,
                    String(store.requestedQuantity(entry)), entry.item.value, entry.item.package, entry.item.lcsc])
            })
            PaginationBar(count: filtered.count, page: $page, pageSize: $pageSize, unit: "requested row")
        }
        .background(Theme.row)
        .onChange(of: project) { page = 0 }
        .onChange(of: query) { page = 0 }
        .onChange(of: pageSize) { page = 0 }
        .onChange(of: filtered.count) { page = min(page, max(0, (filtered.count - 1) / pageSize)) }
    }
}
