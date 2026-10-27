import SwiftUI

struct SupplierFields: View {
    @Binding var spn: String
    @Binding var supplier: String

    var body: some View {
        TextField("Supplier part number (SPN)", text: $spn)
        HStack {
            TextField("Supplier", text: $supplier)
            Menu {
                ForEach(Supplier.suggestions, id: \.self) { name in
                    Button(name) { supplier = name }
                }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Choose a supplier, or type another supplier name")
        }
    }
}
