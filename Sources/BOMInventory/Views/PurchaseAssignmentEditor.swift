import SwiftUI

struct PurchaseAssignmentDraft: Identifiable {
    let id = UUID()
    var itemID: String
    var project: String
    var quantity = 1
    var designators = ""
}

struct PurchaseAssignmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    var store: InventoryStore
    var draft: PurchaseAssignmentDraft
    @State private var itemID: String
    @State private var project: String
    @State private var quantity: String
    @State private var designators: String
    @State private var error: String?
    init(store: InventoryStore, draft: PurchaseAssignmentDraft) {
        self.store = store; self.draft = draft
        _itemID = State(initialValue: draft.itemID.isEmpty ? store.purchases.first?.id ?? "" : draft.itemID)
        _project = State(initialValue: draft.project)
        _quantity = State(initialValue: String(draft.quantity)); _designators = State(initialValue: draft.designators)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Purchase project assignment").font(.headline)
            LabeledContent("Project") {
                SuggestionField(text: $project, placeholder: "", suggestions: store.projects.map(\.name), filterOnTyping: true, choose: { project = $0 }, submit: {}).accessibilityLabel("Project name")
            }
            TextField("Quantity", text: $quantity)
            TextField("Designators", text: $designators).onChange(of: designators) { _, value in
                if let count = try? Designators.quantity(in: value) { quantity = String(count) }
            }
            if let item = store.purchases.first(where: { $0.id == itemID }) { Text("\(item.part.stock) units planned for purchase").font(.caption).foregroundStyle(Theme.muted) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save") {
                    do {
                        guard let count = Int(quantity), count > 0 else { throw InventoryError.message("Enter a positive quantity.") }
                        try store.editPurchaseAssignment(itemID: itemID, originalProject: draft.project.isEmpty ? nil : draft.project, project: project, quantity: count, designators: designators)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(itemID.isEmpty || project.isEmpty).keyboardShortcut(.defaultAction)
            }.buttonStyle(ProjectBOMActionStyle())
        }.padding(24).frame(width: 460).textFieldStyle(.roundedBorder).background(Theme.panel).suggestionOverlay()
    }
}
