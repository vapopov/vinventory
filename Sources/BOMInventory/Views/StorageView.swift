import SwiftUI

struct StorageView: View {
    @Environment(\.inventoryNavigation) private var navigation
    var store: InventoryStore
    var parts: [Part]
    @Binding var locationSelection: String?
    @Binding var partSelection: String?
    var editPart: (Part) -> Void
    var showPart: (Part) -> Void
    @State private var catalogDraft: CatalogDraft?
    @State private var deletingCatalog = false
    @State private var bulkAdding = false
    @State private var checked: Set<String> = []
    @State private var page = 0
    @State private var pageSize = 25
    @FocusState private var locationsFocused: Bool
    private var locations: [StorageLocation] { store.locations }
    private var location: StorageLocation? { locations.first { $0.id == locationSelection } }
    private var assigned: [Part] { guard let location else { return [] }; return parts.filter(location.contains) }
    private var displayed: [Part] {
        guard bulkAdding, let location else { return assigned }
        return parts.filter { !location.contains($0) }
    }
    private var pages: Int { max(1, (displayed.count + pageSize - 1) / pageSize) }
    var body: some View {
        HSplitView {
            locationList.frame(minWidth: 290, idealWidth: 380, maxWidth: 540)
            VStack(spacing: 0) {
                if let location {
                    HStack {
                        Text("INVENTORY IN \(location.displayName.uppercased())").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        Button(action: toggleBulkAdding) {
                            Image(systemName: bulkAdding ? "checkmark" : "plus.square.on.square").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                        }.buttonStyle(.plain).foregroundStyle(Theme.yellow)
                            .help(bulkAdding ? "Apply storage assignments" : "Bulk add parts to storage")
                            .accessibilityLabel(bulkAdding ? "Apply storage assignments" : "Bulk add parts to storage")
                        if bulkAdding {
                            Button { cancelBulkAdding() } label: { Image(systemName: "xmark").frame(width: 26, height: 26) }.buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Cancel bulk adding")
                            Text("\(checked.count) selected").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if !bulkAdding, let part = assigned.first(where: { $0.id == partSelection }) {
                            Button("Edit part") { editPart(part) }.buttonStyle(.plain).foregroundStyle(Theme.yellow)
                        }
                    }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
                    PartsTable(parts: Array(displayed.dropFirst(page * pageSize).prefix(pageSize)), selection: $partSelection,
                        checkedPartIDs: bulkAdding ? checked : nil, checkPart: { id, included in
                            if included { checked.insert(id) } else { checked.remove(id) }
                        }, preview: { part, dismiss in
                        AnyView(PartPreview(store: store, partID: part.id, dismiss: { dismiss() }, editPart: editPart, showPart: showPart).environment(\.inventoryNavigation, navigation))
                    }).id(bulkAdding)
                        .overlay {
                            if displayed.isEmpty { EmptyState(title: "No matching parts", subtitle: bulkAdding ? "All matching parts are already in this location." : "No parts in this location match the current search.").allowsHitTesting(false) }
                        }
                    PaginationBar(count: displayed.count, page: $page, pageSize: $pageSize)
                } else {
                    EmptyState(title: "Select a storage location", subtitle: "Add a storage location or select (no storage).")
                }
            }.frame(minWidth: 710, maxHeight: .infinity).background(Theme.row)
        }
        .sheet(item: $catalogDraft) { draft in
            CatalogEditor(kind: .storage, draft: draft) { name, description in
                let saved = try store.saveCatalog(kind: .storage, originalName: draft.originalName, name: name, description: description)
                locationSelection = StorageLocation(name: saved, description: description).id
            }
        }
        .alert("Delete storage?", isPresented: $deletingCatalog) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let name = location?.name { store.perform { try store.deleteCatalog(kind: .storage, name: name) } }
            }
        } message: { Text("Parts in this storage location will move to (no storage).") }
        .onAppear { reconcileSelection() }
        .onChange(of: locations.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: locationSelection) { _, _ in
            cancelBulkAdding()
            if let partSelection, !assigned.contains(where: { $0.id == partSelection }) { self.partSelection = nil }
        }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .onChange(of: displayed.map(\.id)) { _, ids in
            page = min(page, pages - 1)
            if let partSelection, !ids.contains(partSelection) { self.partSelection = nil }
        }
    }
    private func cancelBulkAdding() { bulkAdding = false; checked = []; page = 0 }
    private func toggleBulkAdding() {
        if bulkAdding {
            guard let location else { return }
            do {
                try store.assignStorage(location.name, partIDs: checked)
                cancelBulkAdding()
            } catch { store.error = error.localizedDescription }
        } else { checked = []; bulkAdding = true; page = 0; partSelection = nil }
    }
    private var locationList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("LOCATIONS").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
            CatalogControls(kind: .storage, editable: location?.name != nil, add: { catalogDraft = CatalogDraft() }, edit: {
                if let item = location, let name = item.name { catalogDraft = CatalogDraft(originalName: name, name: name, description: item.description) }
            }, delete: { deletingCatalog = true })
            }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
            HStack { Text("Name").frame(width: 130, alignment: .leading); Text("Description").frame(maxWidth: .infinity, alignment: .leading) }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 32).background(Theme.raised.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(locations) { item in
                        CatalogRow(name: item.displayName, description: item.description, selected: locationSelection == item.id, select: { locationSelection = item.id })
                    }
                }
            }.focusable().focused($locationsFocused).onMoveCommand { direction in
                guard locationsFocused, direction == .up || direction == .down, !locations.isEmpty else { return }
                let current = locations.firstIndex { $0.id == locationSelection } ?? 0
                let next = min(max(current + (direction == .down ? 1 : -1), 0), locations.count - 1)
                locationSelection = locations[next].id
            }
            HStack { Text("\(locations.count) locations").foregroundStyle(Theme.yellow); Spacer() }.padding(.horizontal, 14).frame(height: 38).background(Theme.raised)
        }.background(Theme.row)
    }
    private func reconcileSelection() {
        if !locations.contains(where: { $0.id == locationSelection }) { locationSelection = locations.first?.id }
    }
}
