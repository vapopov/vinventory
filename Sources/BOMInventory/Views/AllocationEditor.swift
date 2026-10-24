import SwiftUI

struct AllocationEditor: View {
    var store: InventoryStore
    var allocation: Allocation
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int
    @State private var designators: String
    @State private var error: String?
    init(store: InventoryStore, allocation: Allocation) {
        self.store = store; self.allocation = allocation
        _quantity = State(initialValue: allocation.quantity)
        _designators = State(initialValue: allocation.designators)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit allocation — \(allocation.project)").font(.title2.bold())
            LabeledContent("Quantity") { TextField("Quantity", value: $quantity, format: .number) }
            LabeledContent("Designators") { TextField("Designators", text: $designators).help("For example: R1, R2 or C16-C20. Editing references recalculates quantity.") }
                .onChange(of: designators) { _, value in
                    if let count = try? Designators.quantity(in: value) { quantity = count }
                }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    do {
                        try store.updateAllocation(allocationID: allocation.id, quantity: quantity, designators: designators)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 460)
    }
}
