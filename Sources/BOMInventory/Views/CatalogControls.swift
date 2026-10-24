import SwiftUI

struct CatalogControls: View {
    var kind: CatalogKind
    var editable: Bool
    var add: () -> Void
    var edit: () -> Void
    var delete: () -> Void
    var body: some View {
        HStack(spacing: 3) {
            control("plus", title: "Add", action: add)
            control("pencil", title: "Edit", action: edit).disabled(!editable)
            control("trash", title: "Delete", action: delete).disabled(!editable)
        }
    }
    private func control(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.yellow).frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).help("\(title) \(kind.title.lowercased())")
            .accessibilityLabel("\(title) \(kind.title.lowercased())")
    }
}
struct CatalogRow: View {
    var name: String
    var description: String
    var selected: Bool
    var select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Text(name).frame(width: 130, alignment: .leading).lineLimit(1)
                Text(description.isEmpty ? "—" : description).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            }.padding(.horizontal, 14).frame(height: 34).contentShape(Rectangle())
                .background(selected ? Theme.selection : Theme.row)
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct CatalogEditor: View {
    var kind: CatalogKind
    var draft: CatalogDraft
    var save: (String, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var error: String?
    init(kind: CatalogKind, draft: CatalogDraft, save: @escaping (String, String) throws -> Void) {
        self.kind = kind; self.draft = draft; self.save = save
        _name = State(initialValue: draft.name); _description = State(initialValue: draft.description)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(draft.originalName == nil ? "Add" : "Edit") \(kind.title.lowercased())").font(.title2.bold())
            LabeledContent("\(kind.title) name") { TextField("\(kind.title) name", text: $name) }
            LabeledContent("\(kind.title) description") { TextField("\(kind.title) description", text: $description) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { do { try save(name, description); dismiss() } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 460)
    }
}
