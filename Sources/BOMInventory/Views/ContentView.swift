import SwiftUI
struct ContentView: View {
    @Bindable var store: InventoryStore
    @State private var query = ""
    @State private var selection: String?
    @State private var editor: Part?
    @State private var deleting = false
    @State private var scanning = false
    @State private var page = 0
    @State private var pageSize = 25
    @State private var barcodeQuery = ""
    private var results: [Part] { store.search(query) }
    private var selected: Part? { store.parts.first { $0.id == selection } }
    private var pages: Int { max(1, (results.count + pageSize - 1) / pageSize) }
    private var visible: [Part] { Array(results.dropFirst(page * pageSize).prefix(pageSize)) }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HSplitView {
                VStack(spacing: 0) {
                    PartsTable(parts: visible, selection: $selection)
                    pagination
                }.frame(minWidth: 630, idealWidth: 930)
                if let selected {
                    PartDetailView(store: store, part: selected, edit: { editor = selected }).frame(minWidth: 440, idealWidth: 550)
                } else {
                    EmptyState(title: store.parts.isEmpty ? "Your inventory starts here" : "Select a part", subtitle: store.parts.isEmpty ? "Add your first component to track stock, storage, and project allocations." : "Select a row to view its details and manage inventory.").frame(minWidth: 440)
                }
            }
            HStack { Circle().fill(Theme.green).frame(width: 6, height: 6); Text("LOCAL INVENTORY").font(.system(size: 10, weight: .semibold)); Spacer(); Text("SQLite  •  \(store.parts.count) parts").font(.system(size: 11)) }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 26).background(Theme.background)
        }
        .font(.system(size: 13)).background(Theme.background)
        .sheet(item: $editor) { part in PartEditor(part: part, store: store) { updated in try store.save(updated, recordFieldUse: true); selection = updated.id } }
        .alert("Delete part?", isPresented: $deleting) { Button("Cancel", role: .cancel) {}; Button("Delete", role: .destructive) { if let selected { store.perform { try store.delete(selected) }; selection = nil } } } message: { Text("The selected part and its project allocations will be permanently removed.") }
        .alert("Inventory error", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .onChange(of: results.count) { _, _ in page = min(page, pages - 1) }
    }
    private var toolbar: some View {
        HStack(spacing: 5) {
            HStack { Text("PARTS").fontWeight(.bold); Spacer() }.foregroundStyle(Theme.yellow).padding(.horizontal, 14).frame(width: 150, height: 34).background(Theme.raised)
            ToolButton(symbol: "plus", title: "Add part (⌘N)") { editor = Part() }.keyboardShortcut("n")
            ToolButton(symbol: "pencil", title: "Edit selected part (⌘E)") { editor = selected }.disabled(selected == nil).keyboardShortcut("e")
            ToolButton(symbol: "trash", title: "Delete selected part") { deleting = true }.disabled(selected == nil)
            Rectangle().fill(Theme.panel).frame(width: 1, height: 28).padding(.horizontal, 7)
            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.yellow).frame(width: 38, height: 32).background(Theme.purple)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search parts, values, packages…", text: $query).textFieldStyle(.plain).frame(width: 230)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain) }
            }.padding(.horizontal, 10).frame(height: 34).background(Theme.raised)
            ToolButton(symbol: "barcode.viewfinder", title: "Search by barcode") { scanning.toggle() }
                .popover(isPresented: $scanning) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Find by barcode").font(.headline)
                        Text("Scan with a USB scanner or paste a barcode, then press Return.").foregroundStyle(Theme.muted)
                        TextField("Barcode", text: $barcodeQuery).onSubmit { query = barcodeQuery; page = 0; selection = store.search(barcodeQuery).first?.id; scanning = false }
                        Button("Find part") { query = barcodeQuery; page = 0; selection = store.search(barcodeQuery).first?.id; scanning = false }
                    }.padding(20).frame(width: 340)
                }
            Text("BOM INVENTORY").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.background).padding(.horizontal, 14).frame(height: 34).background(Theme.yellow).padding(.leading, 8)
        }.padding(.horizontal, 10).frame(height: 52).background(Theme.background)
    }
    private var pagination: some View {
        HStack(spacing: 12) {
            Text("\(results.count) parts").foregroundStyle(Theme.yellow)
            Spacer()
            pageButton("chevron.left.2", disabled: page == 0) { page = 0 }
            pageButton("chevron.left", disabled: page == 0) { page -= 1 }
            Text("Page \(page + 1) of \(pages)").monospacedDigit()
            pageButton("chevron.right", disabled: page >= pages - 1) { page += 1 }
            pageButton("chevron.right.2", disabled: page >= pages - 1) { page = pages - 1 }
            Text(results.isEmpty ? "0 of 0" : "\(page * pageSize + 1)–\(min((page + 1) * pageSize, results.count)) of \(results.count)").foregroundStyle(Theme.muted).monospacedDigit()
            Picker("Rows", selection: $pageSize) { Text("25").tag(25); Text("50").tag(50); Text("100").tag(100) }.labelsHidden().frame(width: 65)
        }.padding(.horizontal, 12).frame(height: 38).background(Theme.raised)
    }
    private func pageButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).disabled(disabled).accessibilityLabel(icon.contains("right") ? "Next page" : "Previous page")
    }
}
