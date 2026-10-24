import SwiftUI

struct CustomFieldDraft: Identifiable {
    let id = UUID()
    var name = ""
    var value = ""
    static func dictionary(_ rows: [CustomFieldDraft]) throws -> [String: String] {
        var result: [String: String] = [:]
        var seen = Set<String>()
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw InventoryError.message("Enter a name for every custom field or remove it.") }
            guard seen.insert(name.lowercased()).inserted else { throw InventoryError.message("Custom field names must be unique.") }
            result[name] = row.value
        }
        return result
    }
}
struct CustomFieldsEditor: View {
    @Binding var fields: [CustomFieldDraft]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Custom fields")
                Spacer()
                Button { fields.append(CustomFieldDraft()) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Add custom field").accessibilityLabel("Add custom field")
            }
            ForEach($fields) { $field in
                HStack {
                    TextField("Field name", text: $field.name).frame(width: 150)
                    TextField("Value", text: $field.value)
                    Button { fields.removeAll { $0.id == field.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(Theme.yellow).help("Remove custom field").accessibilityLabel("Remove custom field \(field.name)")
                }
            }
        }
    }
}
