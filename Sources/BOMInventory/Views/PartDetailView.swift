import SwiftUI
import AppKit
struct PartDetailView: View {
    @Environment(\.inventoryNavigation) private var navigation
    @Bindable var store: InventoryStore
    var part: Part
    var edit: () -> Void
    @State private var tab = 0
    @State private var allocating = false
    @State private var adjusting = false
    @State private var project = ""
    @State private var quantity = 1
    @State private var designators = ""
    @State private var stock = 0
    @State private var editingAllocation: Allocation?
    var body: some View {
        VSplitView {
            ScrollView {
                PartSummaryView(part: part, available: store.available(part), allocated: store.allocated(part), edit: edit)
            }.background(Theme.panel).frame(minHeight: 300, idealHeight: 390)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    tabButton("Inventory", index: 0)
                    tabButton("Project allocations", index: 1)
                    Spacer()
                }.frame(height: 46).background(Theme.raised)
                HStack(spacing: 8) {
                    ToolButton(symbol: "plus", title: tab == 0 ? "Set stock" : "Allocate to project") { if tab == 0 { stock = part.stock; adjusting = true } else { quantity = 1; project = ""; designators = ""; allocating = true } }
                    Text(tab == 0 ? "Manage physical stock" : "Reserve stock for a project").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                }.padding(8).background(Theme.raised.opacity(0.65))
                if tab == 0 {
                    ScrollView {
                        inventoryRows
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    allocationRows
                }
                HStack { Text(tab == 0 ? "Stock is shared across all project allocations." : "Releasing an allocation returns it to available stock."); Spacer() }.font(.system(size: 11)).foregroundStyle(Theme.muted).padding(12).background(Theme.raised)
            }.background(Theme.row).frame(minHeight: 240)
        }
        .sheet(item: $editingAllocation) { allocation in AllocationEditor(store: store, allocation: allocation) }
        .sheet(isPresented: $allocating) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Allocate to project").font(.title2.bold())
                Text("\(store.available(part)) available • \(part.number)").foregroundStyle(Theme.muted)
                LabeledContent("Project") {
                    SuggestionField(text: $project, placeholder: "", suggestions: store.projects.map(\.name), filterOnTyping: true, choose: { project = $0 }, submit: {}).accessibilityLabel("Project name")
                }
                TextField("Quantity", value: $quantity, format: .number)
                TextField("Designators", text: $designators).help("For example: C16-C20 or R3, R4, R11")
                HStack { Spacer(); Button("Cancel") { allocating = false }; Button("Allocate") { do { try store.allocate(part, project: project, quantity: quantity, designators: designators); allocating = false } catch { store.error = error.localizedDescription; allocating = false } }.keyboardShortcut(.defaultAction) }
            }.textFieldStyle(.roundedBorder).padding(24).frame(width: 430).suggestionOverlay()
        }
        .sheet(isPresented: $adjusting) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Update on-hand stock").font(.title2.bold())
                Text("\(store.allocated(part)) units are allocated to projects.").foregroundStyle(Theme.muted)
                TextField("Total quantity", value: $stock, format: .number)
                HStack { Spacer(); Button("Cancel") { adjusting = false }; Button("Save stock") { var updated = part; updated.stock = stock; do { try store.save(updated); adjusting = false } catch { store.error = error.localizedDescription; adjusting = false } }.keyboardShortcut(.defaultAction) }
            }.textFieldStyle(.roundedBorder).padding(24).frame(width: 390)
        }
    }
    private func tabButton(_ title: String, index: Int) -> some View { Button { tab = index } label: { Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(tab == index ? Color.white : Theme.yellow).padding(.horizontal, 16).frame(height: 46).background(tab == index ? Theme.purple : .clear) }.buttonStyle(.plain) }
    private var inventoryRows: some View {
        VStack(spacing: 1) {
            dataRow("STATUS", "QTY", "STORAGE", header: true)
            dataRow("Available", store.available(part).formatted(), part.storage, color: Theme.green)
            dataRow("Allocated", store.allocated(part).formatted(), "\(store.allocations.filter { $0.partID == part.id }.count) reservations")
            dataRow("On-hand", part.stock.formatted(), part.storage)
        }
    }
    private var allocationRows: some View {
        VStack(spacing: 0) {
            dataRow("PROJECT", "QTY", "", header: true)
            ScrollView {
                VStack(spacing: 0) {
                    let allocations = store.allocations.filter { $0.partID == part.id }
                    if allocations.isEmpty { Text("No project allocations").foregroundStyle(Theme.muted).padding(30) }
                    ForEach(allocations) { allocation in
                        HStack { VStack(alignment: .leading, spacing: 3) { DestinationLink(title: allocation.project, destination: "project") { navigation.project(allocation.project) }; if !allocation.designators.isEmpty { Text(allocation.designators).font(.caption).foregroundStyle(Theme.muted).lineLimit(1) } }; Spacer(); Text(allocation.quantity.formatted()).monospacedDigit(); Button { editingAllocation = allocation } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Edit quantity and designators").accessibilityLabel("Edit allocation for \(allocation.project)").padding(.horizontal, 12); ReleaseAllocationButton(title: allocation.project) { store.perform { try store.release(allocation) } } }.padding(14).background(Theme.panel.opacity(0.6))
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Project allocations list")
        }.frame(maxHeight: .infinity)
    }
    private func dataRow(_ a: String, _ b: String, _ c: String, header: Bool = false, color: Color = .primary) -> some View {
        HStack { Text(a).foregroundStyle(header ? Theme.muted : color).frame(maxWidth: .infinity, alignment: .leading); Text(b).monospacedDigit().frame(width: 60, alignment: .trailing); Text(c).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20) }.font(.system(size: header ? 11 : 13, weight: header ? .medium : .regular)).padding(.horizontal, 16).frame(height: header ? 34 : 42).background(header ? Theme.raised : Theme.panel.opacity(0.45))
    }
}
