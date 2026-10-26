import SwiftUI

struct ProjectPurchasesView: View {
    var store: InventoryStore
    var project: String
    var query: String
    @State private var selection: String?
    @State private var draft: PurchaseAssignmentDraft?
    @State private var page = 0
    @State private var pageSize = 25
    private var items: [PurchaseItem] { store.purchaseSearch(query).filter { $0.assignments.contains { $0.project.caseInsensitiveCompare(project) == .orderedSame } } }
    private var rows: [Allocation] {
        items.compactMap { item in
            item.assignments.first { $0.project.caseInsensitiveCompare(project) == .orderedSame }.map {
                Allocation(id: $0.id, partID: item.id, project: project, quantity: $0.quantity, designators: $0.designators)
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PLANNED PURCHASES").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button { draft = PurchaseAssignmentDraft(itemID: "", project: project) } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Assign a cart item to this project")
            }.padding(.horizontal, 14).frame(height: 32).background(Theme.raised)
            PartsTable(parts: items.map(\.part), selection: $selection, allocations: Array(rows.dropFirst(page * pageSize).prefix(pageSize)), rowNumberOffset: page * pageSize, stockColumnTitle: "To purchase", saveDesignators: { row, value in
                try store.savePurchaseAssignment(itemID: row.partID, project: project, quantity: row.quantity, designators: value, inferQuantity: true)
            }, saveQuantity: { row, value in
                guard let count = Int(value), count > 0 else { throw InventoryError.message("Enter a positive quantity.") }
                try store.savePurchaseAssignment(itemID: row.partID, project: project, quantity: count, designators: row.designators)
            }, releaseAllocation: { row in store.perform { try store.removePurchaseAssignment(itemID: row.partID, project: project) } })
            PaginationBar(count: rows.count, page: $page, pageSize: $pageSize, unit: "purchase")
        }
        .sheet(item: $draft) { PurchaseAssignmentEditor(store: store, draft: $0) }
        .onChange(of: query) { page = 0 }.onChange(of: pageSize) { page = 0 }
        .onChange(of: rows.count) { page = min(page, max(0, (rows.count - 1) / pageSize)) }
    }
}
