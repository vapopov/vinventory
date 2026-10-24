import SwiftUI

/// Compact table-cell editor: hover, pencil, Enter/outside-click saves, Escape cancels.
struct InlineTextCell: View {
    var value: String
    var title: String
    var wraps = false
    var emptyPlaceholder = "—"
    var preview: (() -> Void)? = nil
    var save: (String) throws -> Void
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var error: String?
    @State private var committing = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 4) {
            if editing {
                TextField("", text: $draft).textFieldStyle(.roundedBorder).focused($focused).accessibilityLabel(title)
                    .onSubmit { commit() }
                    .onKeyPress(.escape) { editing = false; focused = false; return .handled }
                    .background {
                        GeometryReader { geometry in
                            OutsideClickMonitor(fieldRect: CGRect(origin: .zero, size: geometry.size), menuRect: .zero, dismiss: commit)
                        }
                    }.task { focused = true }
            } else {
                if let preview {
                    Button(action: preview) { displayText.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Preview \(title)")
                } else { displayText }
            }
            Button { beginEditing() } label: { Image(systemName: "pencil").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.yellow) }
                .buttonStyle(.plain).accessibilityLabel("Edit \(title)").opacity(hovering || editing ? 1 : 0)
                .allowsHitTesting(hovering || editing).accessibilityHidden(!hovering && !editing)
        }.font(.system(size: 13)).padding(.horizontal, 6).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .onHover { hovering = $0 }.accessibilityElement(children: .contain).accessibilityLabel(title)
            .accessibilityAction(named: "Edit \(title)") { beginEditing() }
            .onChange(of: focused) { old, new in if old && !new { commit() } }
            .onDisappear { commit() }
            .alert("Could not save \(title)", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private var displayText: some View {
        Text(value.isEmpty ? emptyPlaceholder : value).lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: wraps).multilineTextAlignment(.leading)
            .help(value).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func beginEditing() { if !editing { draft = value; editing = true }; focused = true }
    private func commit() {
        guard editing, !committing else { return }
        committing = true
        defer { committing = false }
        do {
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != value { try save(trimmed) }
            editing = false
            focused = false
        } catch { self.error = error.localizedDescription }
    }
}
