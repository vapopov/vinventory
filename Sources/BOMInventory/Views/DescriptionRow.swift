import SwiftUI

/// Shared hover-to-edit name/description row for Storage and Projects.
struct DescriptionRow: View {
    var name: String
    var description: String
    var selected: Bool
    var kind: String
    var canEdit = true
    var select: () -> Void
    var save: (String) throws -> Void
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var fieldFocused: Bool
    var body: some View {
        ZStack {
            Button(action: select) {
                Rectangle().fill(selected ? Theme.selection : Theme.row).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(name)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityAction(named: "Edit \(kind) description") { beginEditing() }
            HStack(spacing: 10) {
                Text(name).frame(width: 130, alignment: .leading).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
                if editing {
                    TextField("Description", text: $draft)
                        .textFieldStyle(.roundedBorder).focused($fieldFocused)
                        .accessibilityLabel("Description for \(name)")
                        .onSubmit { commit() }
                        .onKeyPress(.escape) { editing = false; fieldFocused = false; return .handled }
                        .background {
                            GeometryReader { geometry in
                                OutsideClickMonitor(fieldRect: CGRect(origin: .zero, size: geometry.size), menuRect: .zero, dismiss: commit)
                            }
                        }
                        .task { fieldFocused = true }
                } else {
                    Text(description.isEmpty ? "—" : description)
                        .foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1).help(description).allowsHitTesting(false)
                }
                if canEdit {
                    Button { beginEditing() } label: {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.yellow).frame(width: 22, height: 24)
                    }.buttonStyle(.plain).help("Edit \(kind) description")
                        .accessibilityLabel("Edit description for \(name)")
                        .opacity(hovering || editing ? 1 : 0)
                        .allowsHitTesting(hovering || editing).accessibilityHidden(!hovering && !editing)
                }
            }.padding(.horizontal, 14)
        }.frame(height: 34).onHover { hovering = $0 }
            .onChange(of: fieldFocused) { wasFocused, focused in if wasFocused && !focused { commit() } }
            .onDisappear { commit() }
            .alert("Description could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func beginEditing() {
        guard canEdit else { return }
        select()
        if !editing { draft = description; editing = true }
        fieldFocused = true
    }
    private func commit() {
        guard editing else { return }
        do {
            let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if value != description { try save(value) }
            editing = false
            fieldFocused = false
        } catch { self.error = error.localizedDescription }
    }
}
