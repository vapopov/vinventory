import SwiftUI

struct RequestDraft: Identifiable {
    let id = UUID()
    var entry: ProjectBOMEntry?
    var item = ProjectBOMItem(designators: "", package: "", quantity: 1, value: "", lcsc: "")
    init() {}
    init(entry: ProjectBOMEntry, quantity: Int) {
        self.entry = entry; item = entry.item; item.quantity = quantity
    }
}

struct RequestEditor: View {
    @Environment(\.dismiss) private var dismiss
    var draft: RequestDraft
    var save: (ProjectBOMItem) throws -> Void
    @State private var item: ProjectBOMItem
    @State private var quantity: String
    @State private var error: String?
    init(draft: RequestDraft, save: @escaping (ProjectBOMItem) throws -> Void) {
        self.draft = draft; self.save = save
        _item = State(initialValue: draft.item)
        _quantity = State(initialValue: String(draft.item.quantity))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.entry == nil ? "Add requested part" : "Edit requested part").font(.headline)
            Form {
                TextField("Value / Part Number", text: $item.value)
                TextField("Designators", text: $item.designators)
                TextField("Requested quantity", text: $quantity)
                TextField("Package", text: $item.package)
                SupplierFields(spn: $item.spn, supplier: $item.supplier)
            }.textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        guard let count = Int(quantity), count > 0 else { throw InventoryError.message("Enter a positive whole-number quantity.") }
                        item.quantity = count
                        try save(item); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }.buttonStyle(ProjectBOMActionStyle())
        }.padding(24).frame(width: 480).background(Theme.panel)
    }
}
