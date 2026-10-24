import SwiftUI
import AppKit
struct PartDetailView: View {
    @Bindable var store: InventoryStore
    var part: Part
    var edit: () -> Void
    @State private var barcode = false
    @State private var tab = 0
    @State private var allocating = false
    @State private var adjusting = false
    @State private var project = ""
    @State private var quantity = 1
    @State private var stock = 0
    var body: some View {
        VSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(part.manufacturer.isEmpty ? "Manufacturer unspecified" : part.manufacturer).foregroundStyle(Theme.muted).font(.system(size: 16, weight: .medium))
                            Text(part.number).font(.system(size: 26, weight: .bold)).textSelection(.enabled)
                            LabelChips(labels: part.labels)
                        }
                        Spacer()
                        PartImageThumbnail(image: part.image, partNumber: part.number)
                    }
                    Text(part.description.isEmpty ? "No description" : part.description).font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                    HStack {
                        Text([part.value, part.tolerance.isEmpty ? "" : "Tolerance \(part.tolerance)", part.package].filter { !$0.isEmpty }.joined(separator: "  •  ")).foregroundStyle(Theme.muted)
                        Spacer()
                        ToolButton(symbol: "qrcode", title: "Show barcode label") { barcode.toggle() }.popover(isPresented: $barcode) { BarcodePopover(part: part) }
                        Button("Datasheet") { if let url = try? DatasheetReference.url(for: part.datasheet) { NSWorkspace.shared.open(url) } }.buttonStyle(.plain).foregroundStyle(Theme.yellow).padding(9).background(Theme.raised).disabled(part.datasheet.isEmpty).help(part.datasheet.hasPrefix("/") ? "Open local PDF" : "Open datasheet in browser")
                    }
                    HStack(spacing: 8) { metric("On-hand", part.stock); metric("Available", store.available(part), color: Theme.green); metric("Allocated", store.allocated(part)) }
                    HStack { Image(systemName: "archivebox"); Text(part.storage.isEmpty ? "No storage assigned" : part.storage); Spacer(); Button("Edit details", action: edit).buttonStyle(.plain).foregroundStyle(Theme.yellow) }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.padding(24)
            }.background(Theme.panel).frame(minHeight: 300, idealHeight: 390)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    tabButton("Inventory", index: 0)
                    tabButton("Project allocations", index: 1)
                    Spacer()
                }.frame(height: 46).background(Theme.raised)
                HStack(spacing: 8) {
                    ToolButton(symbol: "plus", title: tab == 0 ? "Set stock" : "Allocate to project") { if tab == 0 { stock = part.stock; adjusting = true } else { quantity = 1; project = ""; allocating = true } }
                    Text(tab == 0 ? "Manage physical stock" : "Reserve stock for a project").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                }.padding(8).background(Theme.raised.opacity(0.65))
                if tab == 0 {
                    inventoryRows
                } else {
                    allocationRows
                }
                Spacer(minLength: 0)
                HStack { Text(tab == 0 ? "Stock is shared across all project allocations." : "Releasing an allocation returns it to available stock."); Spacer() }.font(.system(size: 11)).foregroundStyle(Theme.muted).padding(12).background(Theme.raised)
            }.background(Theme.row).frame(minHeight: 240)
        }
        .sheet(isPresented: $allocating) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Allocate to project").font(.title2.bold())
                Text("\(store.available(part)) available • \(part.number)").foregroundStyle(Theme.muted)
                TextField("Project name", text: $project)
                TextField("Quantity", value: $quantity, format: .number)
                HStack { Spacer(); Button("Cancel") { allocating = false }; Button("Allocate") { do { try store.allocate(part, project: project, quantity: quantity); allocating = false } catch { store.error = error.localizedDescription; allocating = false } }.keyboardShortcut(.defaultAction) }
            }.textFieldStyle(.roundedBorder).padding(24).frame(width: 390)
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
    private func metric(_ title: String, _ value: Int, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).foregroundStyle(Theme.muted); Text(value.formatted()).font(.system(size: 20, weight: .medium)).foregroundStyle(color).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(Theme.selection.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
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
            let allocations = store.allocations.filter { $0.partID == part.id }
            if allocations.isEmpty { Text("No project allocations").foregroundStyle(Theme.muted).padding(30) }
            ForEach(allocations) { allocation in
                HStack { Text(allocation.project).lineLimit(1); Spacer(); Text(allocation.quantity.formatted()).monospacedDigit(); Button("Release") { store.perform { try store.release(allocation) } }.buttonStyle(.plain).foregroundStyle(Theme.yellow).padding(.leading, 18) }.padding(14).background(Theme.panel.opacity(0.6))
                Divider()
            }
        }
    }
    private func dataRow(_ a: String, _ b: String, _ c: String, header: Bool = false, color: Color = .primary) -> some View {
        HStack { Text(a).foregroundStyle(header ? Theme.muted : color).frame(maxWidth: .infinity, alignment: .leading); Text(b).monospacedDigit().frame(width: 60, alignment: .trailing); Text(c).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20) }.font(.system(size: header ? 11 : 13, weight: header ? .medium : .regular)).padding(.horizontal, 16).frame(height: header ? 34 : 42).background(header ? Theme.raised : Theme.panel.opacity(0.45))
    }
}
