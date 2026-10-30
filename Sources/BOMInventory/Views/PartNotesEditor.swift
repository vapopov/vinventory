import SwiftUI
import AppKit
@preconcurrency import WebKit

@MainActor final class NotesEditorSession: ObservableObject {
    let draft = AttachmentDraft()
    weak var webView: WKWebView?
    var initialHTML = ""
    var loadFailed = false
    @Published var ready = false
    @Published var saving = false
    @Published var error: String?
    init(notes: PartNotes) {
        do { initialHTML = NotesMathPreview.html(try NotesDocument.load(notes)) }
        catch { self.error = error.localizedDescription; loadFailed = true }
    }
    func command(_ name: String, value: String = "") {
        guard ready, let webView else { return }
        let arguments = [name, value]
        guard let data = try? JSONEncoder().encode(arguments), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.notes.command(...\(json))") { [weak self] _, error in
            if let error { self?.error = error.localizedDescription }
        }
    }
    func paste() {
        let board = NSPasteboard.general
        if board.availableType(from: [.png, .tiff]) != nil, let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            command("insertHTML", value: "<img alt=\"Note image\" src=\"data:image/png;base64,\(png.base64EncodedString())\">")
        } else if let rtf = board.data(forType: .rtf), let rich = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            command("insertHTML", value: NotesMathPreview.html(rich))
        } else if let text = board.string(forType: .string) {
            command("insertHTML", value: NotesMathPreview.escape(text))
        }
    }
    func document() async throws -> PartNotes {
        guard ready, let webView else { throw InventoryError.message("The notes editor is still loading.") }
        let json: String = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("JSON.stringify(window.notes.exportTokens())") { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let json = value as? String { continuation.resume(returning: json) }
                else { continuation.resume(throwing: InventoryError.message("Unable to read the note document.")) }
            }
        }
        let tokens = try JSONDecoder().decode([NotesVisualToken].self, from: Data(json.utf8))
        return try NotesDocument.save(NotesVisualDocument.attributedString(tokens), draft: draft)
    }
}

struct PartNotesEditor: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var save: (PartNotes) throws -> Void
    @StateObject private var session: NotesEditorSession
    init(part: Part, save: @escaping (PartNotes) throws -> Void) {
        self.init(title: part.number, notes: part.notes, save: save)
    }
    init(title: String, notes: PartNotes, save: @escaping (PartNotes) throws -> Void) {
        self.title = title; self.save = save
        _session = StateObject(wrappedValue: NotesEditorSession(notes: notes))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes — \(title)").font(.title2.bold())
            HStack(spacing: 14) {
                Button { session.command("bold") } label: { Image(systemName: "bold") }.help("Bold")
                Button { session.command("italic") } label: { Image(systemName: "italic") }.help("Italic")
                Button { session.command("underline") } label: { Image(systemName: "underline") }.help("Underline")
                Divider().frame(height: 20)
                Button { session.paste() } label: { Label("Paste", systemImage: "clipboard") }.help("Paste text or an image (⌘V)")
                Button { session.command("equation") } label: { Label("Equation", systemImage: "function") }.help("Insert or edit a LaTeX equation")
                Button { session.command("undo") } label: { Image(systemName: "arrow.uturn.backward") }.help("Undo (⌘Z)")
                Button { session.command("redo") } label: { Image(systemName: "arrow.uturn.forward") }.help("Redo (⇧⌘Z)")
                Spacer()
            }.buttonStyle(.bordered).disabled(!session.ready || session.saving)
            Text("Type $…$ or $$…$$ to render math in place. Click an equation to edit it. Paste images with ⌘V.")
                .font(.caption).foregroundStyle(Theme.muted)
            NotesMathWebView(session: session).frame(minHeight: 420)
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(Theme.muted.opacity(0.3)).allowsHitTesting(false) }
                .disabled(session.saving)
            if let error = session.error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(session.saving)
                Button(session.saving ? "Saving…" : "Save notes") {
                    session.saving = true
                    Task { @MainActor in
                        defer { session.saving = false }
                        do { let notes = try await session.document(); try save(notes); dismiss() }
                        catch { session.error = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction).disabled(session.loadFailed || !session.ready || session.saving)
            }.buttonStyle(ProjectBOMActionStyle())
        }.padding(24).frame(minWidth: 900, idealWidth: 1100, maxWidth: .infinity, minHeight: 650, idealHeight: 760, maxHeight: .infinity).background(Theme.panel)
    }
}
