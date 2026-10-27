import SwiftUI

struct ProjectPurchasesView: View {
    @Environment(\.inventoryNavigation) private var navigation
    var store: InventoryStore
    var project: String
    var query: String
    @State private var selection: String?
    @State private var editor: Part?
    var bulkAdding: Bool
    @Binding var drafts: [String: Allocation]
    @State private var page = 0
    @State private var pageSize = 25
    private var items: [PurchaseItem] {
        let matches = Set(store.purchaseSearch(query).map(\.id))
        return store.purchases.filter { item in
            let assigned = item.assignments.contains { $0.project.caseInsensitiveCompare(project) == .orderedSame }
            let textMatch = matches.contains(item.id) || (!query.isEmpty && drafts[item.id]?.designators.localizedCaseInsensitiveContains(query) == true)
            return (bulkAdding ? !assigned : assigned) && textMatch
        }.sorted { $0.part.number.localizedStandardCompare($1.part.number) == .orderedAscending }
    }
    private var rows: [Allocation] {
        items.compactMap { item in
            if bulkAdding { return drafts[item.id] ?? Allocation(id: item.id, partID: item.id, project: project, quantity: 0) }
            return item.assignments.first { $0.project.caseInsensitiveCompare(project) == .orderedSame }.map {
                Allocation(id: $0.id, partID: item.id, project: project, quantity: $0.quantity, designators: $0.designators)
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            PartsTable(parts: items.map(\.part), selection: $selection, allocations: Array(rows.dropFirst(page * pageSize).prefix(pageSize)), rowNumberOffset: page * pageSize, draftMode: bulkAdding, stockColumnTitle: "To purchase", saveDesignators: { row, value in
                if bulkAdding { try updateDraft(row, designators: value) }
                else { try store.savePurchaseAssignment(itemID: row.partID, project: project, quantity: row.quantity, designators: value, inferQuantity: true) }
            }, saveQuantity: { row, value in
                if bulkAdding { try updateDraft(row, quantity: value) }
                else {
                    guard let count = Int(value), count > 0 else { throw InventoryError.message("Enter a positive quantity.") }
                    try store.savePurchaseAssignment(itemID: row.partID, project: project, quantity: count, designators: row.designators)
                }
            }, releaseAllocation: { row in store.perform { try store.removePurchaseAssignment(itemID: row.partID, project: project) } }, preview: { part, dismiss in
                AnyView(PurchasePartPreview(store: store, itemID: part.id, dismiss: { dismiss() }, edit: { editor = $0 }).environment(\.inventoryNavigation, navigation))
            }).id(bulkAdding)
            PaginationBar(count: rows.count, page: $page, pageSize: $pageSize, unit: "purchase")
        }
        .sheet(item: $editor) { part in
            PartEditor(part: part, store: store, purchaseMode: true) { updated in
                guard var item = store.purchases.first(where: { $0.id == updated.id }) else { throw InventoryError.message("Purchase item no longer exists.") }
                item.part = updated; try store.savePurchase(item)
            }
        }
        .onChange(of: query) { page = 0 }.onChange(of: pageSize) { page = 0 }
        .onChange(of: rows.count) { page = min(page, max(0, (rows.count - 1) / pageSize)) }
        .onChange(of: bulkAdding) { page = 0; selection = nil }
    }
    private func updateDraft(_ row: Allocation, quantity: String? = nil, designators: String? = nil) throws {
        var draft = drafts[row.partID] ?? row
        if let quantity {
            if quantity.isEmpty { draft.quantity = 0 }
            else {
                guard let count = Int(quantity), count > 0 else { throw InventoryError.message("Enter a positive quantity.") }
                draft.quantity = count
            }
        }
        if let designators {
            draft.designators = designators.trimmingCharacters(in: .whitespacesAndNewlines)
            if let count = try Designators.quantity(in: draft.designators) { draft.quantity = count }
        }
        drafts[row.partID] = draft
    }
}
