import SwiftUI

struct ProjectsView: View {
    @Environment(\.inventoryNavigation) private var navigation
    var store: InventoryStore
    var query: String
    @Binding var projectSelection: String?
    @Binding var partSelection: String?
    var editPart: (Part) -> Void
    var showPart: (Part) -> Void
    @State private var allocationSelection: String?
    @State private var page = 0
    @State private var pageSize = 25
    @FocusState private var projectsFocused: Bool
    private var project: Project? { store.projects.first { $0.id == projectSelection } }
    private var matching: [Allocation] {
        guard let project else { return [] }
        let matches = Set(store.search(query).map(\.id))
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.allocations.filter { project.contains($0) && (matches.contains($0.partID) || (!text.isEmpty && $0.designators.localizedCaseInsensitiveContains(text))) }
    }
    private var pages: Int { max(1, (matching.count + pageSize - 1) / pageSize) }
    private var rowSelection: Binding<String?> {
        Binding(get: { allocationSelection }, set: { id in
            allocationSelection = id
            partSelection = store.allocations.first { $0.id == id }?.partID
        })
    }
    var body: some View {
        HSplitView {
            projectList.frame(minWidth: 290, idealWidth: 380, maxWidth: 540)
            VStack(spacing: 0) {
                if let project {
                    HStack {
                        Text("ALLOCATIONS IN \(project.name.uppercased())").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(matching.reduce(0) { $0 + $1.quantity }.formatted()) units").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
                    PartsTable(parts: store.parts, selection: rowSelection, allocations: Array(matching.dropFirst(page * pageSize).prefix(pageSize)), rowNumberOffset: page * pageSize, saveDesignators: { allocation, value in
                        try store.saveDesignators(allocationID: allocation.id, value: value)
                    }, saveQuantity: { allocation, value in
                        try store.saveQuantity(allocationID: allocation.id, value: value)
                    }, releaseAllocation: { allocation in
                        store.perform { try store.release(allocation) }
                    }, preview: { part, dismiss in
                        AnyView(PartPreview(store: store, partID: part.id, dismiss: { dismiss() }, editPart: editPart, showPart: showPart).environment(\.inventoryNavigation, navigation))
                    })
                    .overlay {
                        if matching.isEmpty {
                            EmptyState(title: "No allocated parts", subtitle: query.isEmpty ? "Allocate parts to this project from PARTS." : "No allocations match this search.").allowsHitTesting(false)
                        }
                    }
                    PaginationBar(count: matching.count, page: $page, pageSize: $pageSize, unit: "allocation")
                } else {
                    EmptyState(title: "Select a project", subtitle: "Create a project by allocating stock to it from PARTS.")
                }
            }.frame(minWidth: 710, maxHeight: .infinity).background(Theme.row)
        }
        .onAppear { reconcileSelection() }
        .onChange(of: store.projects.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: projectSelection) { _, _ in page = 0; allocationSelection = nil; partSelection = nil }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .onChange(of: matching.map(\.id)) { _, ids in
            page = min(page, pages - 1)
            if let allocationSelection, !ids.contains(allocationSelection) { self.allocationSelection = nil; partSelection = nil }
        }
    }
    private var projectList: some View {
        VStack(spacing: 0) {
            HStack { Text("PROJECTS").font(.system(size: 12, weight: .semibold)); Spacer() }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
            HStack { Text("Name").frame(width: 130, alignment: .leading); Text("Description").frame(maxWidth: .infinity, alignment: .leading) }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 32).background(Theme.raised.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.projects) { project in
                        DescriptionRow(name: project.name, description: project.description, selected: projectSelection == project.id, kind: "project", select: { projectSelection = project.id }) { description in
                            try store.saveProjectDescription(name: project.name, description: description)
                        }
                    }
                }
            }.focusable().focused($projectsFocused).onMoveCommand { direction in
                guard projectsFocused, direction == .up || direction == .down, !store.projects.isEmpty else { return }
                let current = store.projects.firstIndex { $0.id == projectSelection } ?? 0
                let next = min(max(current + (direction == .down ? 1 : -1), 0), store.projects.count - 1)
                projectSelection = store.projects[next].id
            }
            HStack { Text("\(store.projects.count) projects").foregroundStyle(Theme.yellow); Spacer() }.padding(.horizontal, 14).frame(height: 38).background(Theme.raised)
        }.background(Theme.row)
    }
    private func reconcileSelection() {
        if !store.projects.contains(where: { $0.id == projectSelection }) { projectSelection = store.projects.first?.id }
    }
}
