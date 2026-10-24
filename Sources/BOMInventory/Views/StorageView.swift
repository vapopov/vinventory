import SwiftUI

struct StorageView: View {
    var store: InventoryStore
    var parts: [Part]
    @Binding var locationSelection: String?
    @Binding var partSelection: String?
    var editPart: (Part) -> Void
    @State private var page = 0
    @State private var pageSize = 25
    @FocusState private var locationsFocused: Bool
    private var locations: [StorageLocation] { store.locations }
    private var location: StorageLocation? { locations.first { $0.id == locationSelection } }
    private var assigned: [Part] { guard let location else { return [] }; return parts.filter(location.contains) }
    private var pages: Int { max(1, (assigned.count + pageSize - 1) / pageSize) }
    var body: some View {
        HSplitView {
            locationList.frame(minWidth: 290, idealWidth: 380, maxWidth: 540)
            VStack(spacing: 0) {
                if let location {
                    HStack {
                        Text("INVENTORY IN \(location.displayName.uppercased())").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        Spacer()
                        if let part = assigned.first(where: { $0.id == partSelection }) {
                            Button("Edit part") { editPart(part) }.buttonStyle(.plain).foregroundStyle(Theme.yellow)
                        }
                    }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
                    PartsTable(parts: Array(assigned.dropFirst(page * pageSize).prefix(pageSize)), selection: $partSelection)
                        .overlay {
                            if assigned.isEmpty { EmptyState(title: "No matching parts", subtitle: "No parts in this location match the current search.").allowsHitTesting(false) }
                        }
                    PaginationBar(count: assigned.count, page: $page, pageSize: $pageSize)
                } else {
                    EmptyState(title: "Select a storage location", subtitle: "Assign storage to a part to see it here.")
                }
            }.frame(minWidth: 710, maxHeight: .infinity).background(Theme.row)
        }
        .onAppear { reconcileSelection() }
        .onChange(of: locations.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: locationSelection) { _, _ in
            page = 0
            if let partSelection, !assigned.contains(where: { $0.id == partSelection }) { self.partSelection = nil }
        }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .onChange(of: assigned.map(\.id)) { _, ids in
            page = min(page, pages - 1)
            if let partSelection, !ids.contains(partSelection) { self.partSelection = nil }
        }
    }
    private var locationList: some View {
        VStack(spacing: 0) {
            HStack { Text("LOCATIONS").font(.system(size: 12, weight: .semibold)); Spacer() }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
            HStack { Text("Name").frame(width: 130, alignment: .leading); Text("Description").frame(maxWidth: .infinity, alignment: .leading) }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 32).background(Theme.raised.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(locations) { item in
                        StorageLocationRow(location: item, selected: locationSelection == item.id, select: { locationSelection = item.id }) { description in
                            if let name = item.name { try store.saveStorageDescription(name: name, description: description) }
                        }
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
