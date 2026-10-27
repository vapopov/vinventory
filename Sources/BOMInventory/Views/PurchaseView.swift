import SwiftUI

struct PurchaseView: View {
    var store: InventoryStore
    var query: String
    var labelFilters: Set<String>
    @Binding var selection: String?
    var edit: (Part) -> Void
    @State private var receiving = false
    @State private var checked: Set<String> = []
    @State private var page = 0
    @State private var pageSize = 25
    @State private var assignmentDraft: PurchaseAssignmentDraft?
    private var items: [PurchaseItem] {
        store.purchaseSearch(query).filter { item in
            labelFilters.isEmpty || item.part.labels.contains { label in
                labelFilters.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
            }
        }
    }
    private var selected: PurchaseItem? { store.purchases.first { $0.id == selection } }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("PURCHASE").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    PurchaseExportButton(store: store)
                    Button {
                        if receiving {
                            store.perform { try store.receivePurchases(ids: checked); receiving = false; checked = []; selection = nil }
                        } else { receiving = true; checked = [] }
                    } label: { Image(systemName: receiving ? "checkmark" : "tray.and.arrow.down").frame(width: 26, height: 26) }
                        .buttonStyle(.plain).foregroundStyle(Theme.yellow).disabled(receiving && checked.isEmpty).help(receiving ? "Receive selected items into PARTS" : "Bulk receive purchases")
                        .accessibilityLabel(receiving ? "Apply received purchases" : "Bulk receive purchases")
                    if receiving {
                        Button { receiving = false; checked = [] } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Cancel receiving")
                        Text("\(checked.count) selected").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
                PartsTable(parts: Array(items.dropFirst(page * pageSize).prefix(pageSize)).map(\.part), selection: $selection, stockColumnTitle: "To purchase", checkedPartIDs: receiving ? checked : nil, doubleClick: edit, checkPart: { id, included in
                    if included { checked.insert(id) } else { checked.remove(id) }
                }).id(receiving)
                PaginationBar(count: items.count, page: $page, pageSize: $pageSize, unit: "purchase item")
            }.frame(minWidth: 630, idealWidth: 930)
            if let item = selected {
                PersistentVerticalSplit(key: "purchase.details.summaryFraction") {
                    ScrollView {
                        PartSummaryView(store: store, part: item.part, available: item.availableQuantity, allocated: item.allocatedQuantity, projects: item.assignments.count, purchaseMode: true, edit: { edit(item.part) })
                    }
                } bottom: {
                    VStack(spacing: 0) {
                    HStack {
                        Text("PROJECT PURCHASES").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        Spacer()
                        Button { assignmentDraft = PurchaseAssignmentDraft(itemID: item.id, project: "") } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Assign purchase to project")
                    }.padding(14).background(Theme.raised)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(item.assignments) { assignment in
                                HStack {
                                    VStack(alignment: .leading) { Text(assignment.project); Text(assignment.designators).font(.caption).foregroundStyle(Theme.muted) }
                                    Spacer(); Text("\(assignment.quantity)")
                                    Button { assignmentDraft = PurchaseAssignmentDraft(itemID: item.id, project: assignment.project, quantity: assignment.quantity, designators: assignment.designators) } label: { Image(systemName: "pencil") }
                                    Button { store.perform { try store.removePurchaseAssignment(itemID: item.id, project: assignment.project) } } label: { Image(systemName: "minus.circle") }
                                }.buttonStyle(.plain).padding(14).background(Theme.panel)
                            }
                        }
                    }.frame(maxHeight: .infinity)
                    }
                }.frame(minWidth: 440, idealWidth: 550).background(Theme.panel)
            } else { EmptyState(title: "Select a purchase item", subtitle: "Add components to plan purchases, assign projects, and receive stock.").frame(minWidth: 440) }
        }
        .sheet(item: $assignmentDraft) { PurchaseAssignmentEditor(store: store, draft: $0) }
        .onChange(of: query) { page = 0 }
        .onChange(of: labelFilters) { page = 0 }
        .onChange(of: pageSize) { page = 0 }
        .onChange(of: items.count) { page = min(page, max(0, (items.count - 1) / pageSize)); checked.formIntersection(Set(store.purchases.map(\.id))) }
    }
}
