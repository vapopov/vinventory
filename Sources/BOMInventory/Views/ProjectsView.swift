import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProjectsView: View {
    @Environment(\.inventoryNavigation) private var navigation
    var store: InventoryStore
    var query: String
    @Binding var projectSelection: String?
    @Binding var partSelection: String?
    var editPart: (Part) -> Void
    var showPart: (Part) -> Void
    @State private var bomImport: ProjectBOMImport?
    @State private var requestedTab = false
    @State private var purchaseTab = false
    @State private var bulkAdding = false
    @State private var bulkDrafts: [String: Allocation] = [:]
    @State private var allocationSelection: String?
    @State private var catalogDraft: CatalogDraft?
    @State private var deletingCatalog = false
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
    private var displayed: [Allocation] {
        guard bulkAdding, let project else { return matching }
        let assigned = Set(store.allocations.filter(project.contains).map(\.partID))
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = Set(store.search(query).map(\.id))
        return store.parts.filter { !assigned.contains($0.id) && (matches.contains($0.id) || (!search.isEmpty && bulkDrafts[$0.id]?.designators.localizedCaseInsensitiveContains(search) == true)) }
            .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
            .map { bulkDrafts[$0.id] ?? Allocation(id: $0.id, partID: $0.id, project: project.name, quantity: 0) }
    }
    private var headerUnits: Int {
        guard let project else { return 0 }
        if purchaseTab {
            return store.purchases.flatMap(\.assignments).filter { $0.project.caseInsensitiveCompare(project.name) == .orderedSame }.reduce(0) { $0 + $1.quantity }
        }
        if requestedTab { return store.bomEntries(for: project.name).reduce(0) { $0 + store.requestedQuantity($1) } }
        return (bulkAdding ? Array(bulkDrafts.values) : matching).reduce(0) { $0 + $1.quantity }
    }
    private var pendingCount: Int { bulkDrafts.values.filter { $0.quantity != 0 || !$0.designators.isEmpty }.count }
    private var pages: Int { max(1, (displayed.count + pageSize - 1) / pageSize) }
    private var rowSelection: Binding<String?> {
        Binding(get: { allocationSelection }, set: { id in
            allocationSelection = id
            partSelection = (bulkAdding ? displayed : store.allocations).first { $0.id == id }?.partID
        })
    }
    var body: some View {
        HSplitView {
            projectList.frame(minWidth: 290, idealWidth: 380, maxWidth: 540)
            VStack(spacing: 0) {
                if let project {
                    HStack {
                        Text("ALLOCATIONS IN \(project.name.uppercased())").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        Button(action: toggleBulkAdding) {
                            Image(systemName: bulkAdding ? "checkmark" : "plus.square.on.square").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                        }.buttonStyle(.plain).foregroundStyle(Theme.yellow).help(bulkAdding ? "Apply bulk allocations" : "Bulk add parts")
                            .accessibilityLabel(bulkAdding ? "Apply bulk allocations" : "Bulk add parts").disabled(bomImport != nil || requestedTab || purchaseTab)
                        Button(action: chooseProjectBOM) { Image(systemName: "arrow.down.to.line").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26) }
                            .buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Import project BOM").accessibilityLabel("Import project BOM").disabled(bulkAdding || bomImport != nil)
                        HStack(spacing: 0) {
                        Button("Allocated") { requestedTab = false; purchaseTab = false }.buttonStyle(ProjectBOMTabStyle(selected: !requestedTab && !purchaseTab)).disabled(bomImport != nil || bulkAdding)
                        Button("Requested") { requestedTab = true; purchaseTab = false }.buttonStyle(ProjectBOMTabStyle(selected: requestedTab)).disabled(bomImport != nil || bulkAdding)
                        Button("Purchase") { requestedTab = false; purchaseTab = true }.buttonStyle(ProjectBOMTabStyle(selected: purchaseTab)).disabled(bomImport != nil || bulkAdding)
                        }
                        if requestedTab && bomImport == nil {
                            Button(action: exportRequested) { Image(systemName: "arrow.up.to.line").frame(width: 26, height: 26) }
                                .buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Export requested BOM as CSV").accessibilityLabel("Export requested BOM")
                        }
                        if bulkAdding {
                            Button { cancelBulkAdding() } label: { Image(systemName: "xmark").frame(width: 26, height: 26) }
                                .buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Cancel bulk adding").accessibilityLabel("Cancel bulk adding")
                            Text("\(pendingCount) pending").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("\(headerUnits.formatted()) units").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
                    if let review = bomImport {
                        ProjectBOMImportView(document: review, project: project.name, store: store, finish: { bomImport = nil }, editPart: editPart, showPart: showPart).id(review.id)
                    } else if purchaseTab {
                        ProjectPurchasesView(store: store, project: project.name, query: query).id(project.id)
                    } else if requestedTab {
                        ProjectRequestsView(store: store, project: project.name, query: query)
                    } else {
                    PartsTable(parts: store.parts, selection: rowSelection, allocations: Array(displayed.dropFirst(page * pageSize).prefix(pageSize)), rowNumberOffset: page * pageSize, draftMode: bulkAdding, saveDesignators: { allocation, value in
                        if bulkAdding { try updateBulkDraft(allocation, designators: value) }
                        else { try store.saveDesignators(allocationID: allocation.id, value: value) }
                    }, saveQuantity: { allocation, value in
                        if bulkAdding { try updateBulkDraft(allocation, quantity: value) }
                        else { try store.saveQuantity(allocationID: allocation.id, value: value) }
                    }, releaseAllocation: { allocation in
                        store.perform { try store.release(allocation) }
                    }, preview: { part, dismiss in
                        AnyView(PartPreview(store: store, partID: part.id, dismiss: { dismiss() }, editPart: editPart, showPart: showPart).environment(\.inventoryNavigation, navigation))
                    })
                    .id(bulkAdding)
                    .overlay {
                        if displayed.isEmpty {
                            EmptyState(title: bulkAdding ? "No unallocated parts" : "No allocated parts", subtitle: query.isEmpty ? (bulkAdding ? "All parts are already allocated to this project." : "Use bulk add or allocate parts from PARTS.") : "No parts match this search.").allowsHitTesting(false)
                        }
                    }
                    PaginationBar(count: displayed.count, page: $page, pageSize: $pageSize, unit: bulkAdding ? "part" : "allocation")
                    }
                } else {
                    EmptyState(title: "Select a project", subtitle: "Add a project or allocate stock from PARTS.")
                }
            }.frame(minWidth: 710, maxHeight: .infinity).background(Theme.row)
        }
        .sheet(item: $catalogDraft) { draft in
            CatalogEditor(kind: .project, draft: draft) { name, description in
                let saved = try store.saveCatalog(kind: .project, originalName: draft.originalName, name: name, description: description)
                projectSelection = saved
            }
        }
        .alert("Delete project?", isPresented: $deletingCatalog) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let name = project?.name { store.perform { try store.deleteCatalog(kind: .project, name: name) } }
            }
        } message: { Text("All allocations in this project will be released back to available stock.") }
        .onAppear { reconcileSelection() }
        .onChange(of: store.projects.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: projectSelection) { _, _ in page = 0; allocationSelection = nil; partSelection = nil; cancelBulkAdding(); bomImport = nil; requestedTab = false; purchaseTab = false }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .onChange(of: displayed.map(\.id)) { _, ids in
            page = min(page, pages - 1)
            if let allocationSelection, !ids.contains(allocationSelection) { self.allocationSelection = nil; partSelection = nil }
        }
    }
    private func chooseProjectBOM() {
        guard let project else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, .plainText]; panel.allowsMultipleSelection = false; panel.prompt = "Review project BOM"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw InventoryError.message("Use a UTF-8 or UTF-16 CSV file.") }
            bomImport = try ProjectBOMImport(text: text, filename: url.lastPathComponent, parts: store.parts, previous: store.bomEntries(for: project.name))
        } catch { store.error = error.localizedDescription }
    }
    private func exportRequested() {
        guard let project else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = project.name + "-requested.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.perform { try store.requestedCSV(project: project.name).write(to: url, atomically: true, encoding: .utf8) }
    }
    private func cancelBulkAdding() {
        bulkAdding = false; bulkDrafts = [:]; page = 0; allocationSelection = nil
    }
    private func toggleBulkAdding() {
        if bulkAdding {
            guard let project else { return }
            do {
                try store.allocateBulk(projectName: project.name, drafts: bulkDrafts.values.sorted { $0.partID < $1.partID })
                cancelBulkAdding()
            } catch { store.error = error.localizedDescription }
        } else {
            bulkDrafts = [:]; bulkAdding = true; page = 0; allocationSelection = nil; partSelection = nil
        }
    }
    private func updateBulkDraft(_ row: Allocation, quantity: String? = nil, designators: String? = nil) throws {
        var draft = bulkDrafts[row.partID] ?? row
        if let quantity {
            if quantity.isEmpty { draft.quantity = 0 }
            else {
                guard let count = Int(quantity), count > 0 else { throw InventoryError.message("Enter a positive whole-number quantity.") }
                draft.quantity = count
            }
        }
        if let designators {
            draft.designators = designators.trimmingCharacters(in: .whitespacesAndNewlines)
            if let count = try Designators.quantity(in: draft.designators) { draft.quantity = count }
        }
        bulkDrafts[row.partID] = draft
    }
    private var projectList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("PROJECTS").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
            CatalogControls(kind: .project, editable: project != nil, add: { catalogDraft = CatalogDraft() }, edit: {
                if let item = project { catalogDraft = CatalogDraft(originalName: item.name, name: item.name, description: item.description) }
            }, delete: { deletingCatalog = true })
            }.padding(.horizontal, 14).frame(height: 40).background(Theme.raised)
            HStack { Text("Name").frame(width: 130, alignment: .leading); Text("Description").frame(maxWidth: .infinity, alignment: .leading) }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 32).background(Theme.raised.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.projects) { project in
                        CatalogRow(name: project.name, description: project.description, selected: projectSelection == project.id, select: { projectSelection = project.id })
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
