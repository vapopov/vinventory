import SwiftUI
import AppKit
import UniformTypeIdentifiers
struct ContentView: View {
    @Bindable var store: InventoryStore
    @StateObject private var api: InventoryAPIServer
    @State private var apiSettings = false
    init(store: InventoryStore) {
        self.store = store
        _api = StateObject(wrappedValue: InventoryAPIServer(store: store))
    }
    @State private var query = ""
    @State private var labelFilters: Set<String> = []
    @State private var showingLabelFilters = false
    @State private var section = InventorySection.parts
    @State private var storageSelection: String?
    @State private var projectSelection: String?
    @State private var selection: String?
    @State private var importDocument: BOMImport?
    @State private var editor: Part?
    @State private var deleting = false
    @State private var cameraScanning = false
    @State private var page = 0
    @State private var pageSize = 25
    @State private var barcodeQuery = ""
    private var results: [Part] {
        store.search(query).filter { part in
            section != .parts || labelFilters.isEmpty || part.labels.contains { label in
                labelFilters.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
            }
        }
    }
    private var selected: Part? { store.parts.first { $0.id == selection } }
    private var pages: Int { max(1, (results.count + pageSize - 1) / pageSize) }
    private var visible: [Part] { Array(results.dropFirst(page * pageSize).prefix(pageSize)) }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let document = importDocument {
                BOMImportView(document: document, store: store, finish: { importDocument = nil }).id(document.id)
            } else if section == .parts {
                HSplitView {
                    VStack(spacing: 0) {
                        PartsTable(parts: visible, selection: $selection, doubleClick: { editor = $0 })
                        PaginationBar(count: results.count, page: $page, pageSize: $pageSize)
                    }.frame(minWidth: 630, idealWidth: 930)
                    if let selected {
                        PartDetailView(store: store, part: selected, edit: { editor = selected }).frame(minWidth: 440, idealWidth: 550)
                    } else {
                        EmptyState(title: store.parts.isEmpty ? "Your inventory starts here" : "Select a part", subtitle: store.parts.isEmpty ? "Add your first component to track stock, storage, and project allocations." : "Select a row to view its details and manage inventory.").frame(minWidth: 440)
                    }
                }
            } else if section == .storage {
                StorageView(store: store, parts: results, locationSelection: $storageSelection, partSelection: $selection, editPart: { editor = $0 }, showPart: navigateToPart)
            } else {
                ProjectsView(store: store, query: query, projectSelection: $projectSelection, partSelection: $selection, editPart: { editor = $0 }, showPart: navigateToPart)
            }
            HStack { Circle().fill(Theme.green).frame(width: 6, height: 6); Text("LOCAL INVENTORY").font(.system(size: 10, weight: .semibold)); Spacer(); Text("SQLite  •  \(store.parts.count) parts").font(.system(size: 11))
                Button { apiSettings.toggle() } label: {
                    Text("API").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.green.opacity(api.running ? 1 : 0.65), in: RoundedRectangle(cornerRadius: 3))
                }.buttonStyle(.plain).help("Configure HTTP API server").accessibilityLabel("API server settings")
                    .popover(isPresented: $apiSettings) { APISettingsPopover(server: api) } }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 26).background(Theme.background)
        }
        .environment(\.inventoryNavigation, InventoryNavigation(project: navigateToProject, storage: navigateToStorage))
        .font(.system(size: 13)).background(Theme.background)
        .sheet(isPresented: $cameraScanning) {
            CameraBarcodeScanner { code in barcodeQuery = code; section = .parts; importDocument = nil; findBarcode() }
        }
        .sheet(item: $editor) { part in PartEditor(part: part, store: store) { updated in try store.save(updated, recordFieldUse: true); selection = updated.id } }
        .alert("Delete part?", isPresented: $deleting) { Button("Cancel", role: .cancel) {}; Button("Delete", role: .destructive) { if let selected { store.perform { try store.delete(selected) }; selection = nil } } } message: { Text("The selected part and its project allocations will be permanently removed.") }
        .alert("Inventory error", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: labelFilters) { _, _ in page = 0 }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .onChange(of: results.count) { _, _ in page = min(page, pages - 1) }
    }
    private var toolbar: some View {
        HStack(spacing: 5) {
            ViewSwitcher(selection: Binding(get: { section }, set: { section = $0; selection = nil; importDocument = nil }))
            ToolButton(symbol: "plus", title: "Add part (⌘N)") {
                var part = Part()
                if section == .storage { part.storage = store.locations.first { $0.id == storageSelection }?.name ?? "" }
                editor = part
            }.keyboardShortcut("n")
            ToolButton(symbol: "pencil", title: "Edit selected part (⌘E)") { editor = selected }.disabled(selected == nil).keyboardShortcut("e")
            ToolButton(symbol: "trash", title: "Delete selected part") { deleting = true }.disabled(selected == nil)
            if section == .parts {
                Button { showingLabelFilters.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                        if !labelFilters.isEmpty { Text("\(labelFilters.count)").font(.system(size: 10, weight: .semibold)) }
                    }.font(.system(size: 15, weight: .semibold)).frame(minWidth: 38).frame(height: 32)
                        .foregroundStyle(Theme.yellow).background(labelFilters.isEmpty ? Theme.raised : Theme.purple)
                }.buttonStyle(.plain).help("Filter parts by labels").accessibilityLabel("Filter parts by labels")
                    .popover(isPresented: $showingLabelFilters) { LabelFilterPopover(labels: store.labels, selected: $labelFilters) }
            }
            Rectangle().fill(Theme.panel).frame(width: 1, height: 28).padding(.horizontal, 7)
            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.yellow).frame(width: 38, height: 32).background(Theme.purple)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField(section == .parts ? "Search parts, values, packages…" : (section == .storage ? "Search parts in storage…" : "Search parts or designators…"), text: $query).textFieldStyle(.plain).frame(width: 230)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain) }
            }.padding(.horizontal, 10).frame(height: 34).background(Theme.raised)
            ToolButton(symbol: "barcode.viewfinder", title: "Scan barcode with camera") { cameraScanning = true }
            ToolButton(symbol: "arrow.down.to.line", title: "Import parts from CSV") { chooseImportFile() }.disabled(importDocument != nil)
            Image(nsImage: AppBrand.icon).resizable().interpolation(.high).scaledToFit().frame(width: 34, height: 34).padding(.leading, 8).accessibilityLabel("BOM Inventory logo")
        }.padding(.horizontal, 10).frame(height: 52).background(Theme.background)
    }
    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.prompt = "Review import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw InventoryError.message("Use a UTF-8 or UTF-16 CSV file.") }
            importDocument = try BOMImport(text: text, filename: url.lastPathComponent)
        } catch { store.error = error.localizedDescription }
    }
    private func navigateToProject(_ name: String) {
        guard let project = store.projects.first(where: { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) else { return }
        query = ""
        selection = nil
        projectSelection = project.id
        section = .projects
    }
    private func navigateToStorage(_ name: String) {
        guard let location = store.locations.first(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        query = ""
        selection = nil
        storageSelection = location.id
        section = .storage
    }
    private func navigateToPart(_ part: Part) {
        if !results.contains(where: { $0.id == part.id }) { labelFilters.removeAll(); query = part.barcode }
        section = .parts
        selection = part.id
        page = (results.firstIndex { $0.id == part.id } ?? 0) / pageSize
    }
    private func findBarcode() {
        labelFilters.removeAll()
        query = barcodeQuery
        page = 0
        if let part = store.search(barcodeQuery).first {
            if section == .storage { storageSelection = store.locations.first { $0.contains(part) }?.id }
            if section == .projects, let allocation = store.allocations.first(where: { $0.partID == part.id }) {
                projectSelection = store.projects.first { $0.contains(allocation) }?.id
            }
            selection = part.id
        } else { selection = nil }
    }
}
