import SwiftUI

struct ProjectRequestsView: View {
    var store: InventoryStore
    var project: String
    var query: String
    private var entries: [ProjectBOMEntry] {
        store.bomEntries(for: project).filter { entry in
            store.requestedQuantity(entry) > 0 && (query.isEmpty || [entry.item.designators, entry.item.value, entry.item.package, entry.item.supplier + " " + entry.item.spn].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    @State private var selection: String?
    @State private var draft: RequestDraft?
    @State private var deleting = false
    @State private var syncMessage: String?
    @State private var reviewingSync = false
    @State private var syncMatches: [String: String] = [:]
    private var selected: ProjectBOMEntry? { entries.first { $0.id == selection } }
    @State private var page = 0
    @State private var pageSize = 25

    var body: some View {
        let filtered = entries
        let offset = min(page * pageSize, filtered.count)
        let visible = filtered.dropFirst(offset).prefix(pageSize)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { draft = RequestDraft() } label: { Image(systemName: "plus") }.disabled(reviewingSync).help("Add requested part").accessibilityLabel("Add requested part")
                Button { if let selected { draft = RequestDraft(entry: selected, quantity: store.requestedQuantity(selected)) } } label: { Image(systemName: "pencil") }.disabled(selected == nil || reviewingSync).help("Edit requested part").accessibilityLabel("Edit requested part")
                Button { deleting = true } label: { Image(systemName: "trash") }.disabled(selected == nil || reviewingSync).help("Delete requested part").accessibilityLabel("Delete requested part")
                Button {
                    if reviewingSync {
                        store.perform {
                            let count = try store.syncRequests(project: project, matches: syncMatches)
                            syncMessage = "Allocated \(count) unit\(count == 1 ? "" : "s")"
                            reviewingSync = false; syncMatches = [:]
                        }
                    } else {
                        syncMatches = [:]; syncMessage = nil; reviewingSync = true
                    }
                } label: { Image(systemName: reviewingSync ? "checkmark" : "arrow.triangle.2.circlepath") }
                    .help(reviewingSync ? "Apply checked matches" : "Review matches with available inventory")
                    .accessibilityLabel(reviewingSync ? "Apply requested matches" : "Sync requested parts")
                if reviewingSync {
                    Button { reviewingSync = false; syncMatches = [:] } label: { Image(systemName: "xmark") }
                        .help("Cancel sync").accessibilityLabel("Cancel sync")
                }
                if let syncMessage { Text(syncMessage).font(.caption).foregroundStyle(Theme.muted) }
                Spacer()
            }.buttonStyle(.plain).foregroundStyle(Theme.yellow).padding(.horizontal, 14).frame(height: 32).background(Theme.raised)

            if reviewingSync {
                RequestSyncReview(store: store, entries: filtered, matches: $syncMatches)
            } else {
            ProjectRequestsTable(rows: visible.enumerated().map { index, entry in
                ProjectRequestRow(id: entry.id, values: [String(offset + index + 1), entry.item.designators,
                    String(store.requestedQuantity(entry)), entry.item.value, entry.item.package, entry.item.supplier + " " + entry.item.spn])
            }, selection: $selection)
            PaginationBar(count: filtered.count, page: $page, pageSize: $pageSize, unit: "requested row")
            }
        }
        .background(Theme.row)
        .sheet(item: $draft) { draft in
            RequestEditor(draft: draft) { item in try store.saveRequest(project: project, existing: draft.entry, item: item) }
        }
        .alert("Delete requested part?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { if let selected { store.perform { try store.deleteRequest(selected) } } }
        } message: { Text("Remove this request. Any stock already allocated will be kept.") }
        .onChange(of: project) { page = 0; reviewingSync = false; syncMatches = [:] }
        .onChange(of: query) { page = 0 }
        .onChange(of: pageSize) { page = 0 }
        .onChange(of: filtered.count) { page = min(page, max(0, (filtered.count - 1) / pageSize)) }
    }
}
