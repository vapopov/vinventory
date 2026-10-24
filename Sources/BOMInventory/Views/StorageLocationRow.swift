import SwiftUI

struct StorageLocationRow: View {
    var location: StorageLocation
    var selected: Bool
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
            }.buttonStyle(.plain).accessibilityLabel(location.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityAction(named: "Edit storage description") { beginEditing() }
            HStack(spacing: 10) {
                Text(location.displayName).frame(width: 130, alignment: .leading).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
                if editing {
                    TextField("Description", text: $draft)
                        .textFieldStyle(.roundedBorder).focused($fieldFocused)
                        .accessibilityLabel("Description for \(location.displayName)")
                        .onSubmit { commit() }
                        .onKeyPress(.escape) { editing = false; fieldFocused = false; return .handled }
                        .background {
                            GeometryReader { geometry in
                                OutsideClickMonitor(fieldRect: CGRect(origin: .zero, size: geometry.size), menuRect: .zero, dismiss: commit)
                            }
                        }
                        .task { fieldFocused = true }
                } else {
                    Text(location.description.isEmpty ? "—" : location.description)
                        .foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1).help(location.description).allowsHitTesting(false)
                }
                if location.name != nil {
                    Button { beginEditing() } label: {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.yellow).frame(width: 22, height: 24)
                    }.buttonStyle(.plain).help("Edit storage description")
                        .accessibilityLabel("Edit description for \(location.displayName)")
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
        guard location.name != nil else { return }
        select()
        if !editing { draft = location.description; editing = true }
        fieldFocused = true
    }
    private func commit() {
        guard editing else { return }
        do {
            let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if value != location.description { try save(value) }
            editing = false
            fieldFocused = false
        } catch { self.error = error.localizedDescription }
    }
}
