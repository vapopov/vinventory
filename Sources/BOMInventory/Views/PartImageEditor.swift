import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PartImageEditor: View {
    @Binding var image: PartImage?
    var draft: AttachmentDraft
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image, let preview = NSImage(contentsOfFile: image.thumbnailPath) {
                            Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit)
                        } else { Image(systemName: "photo").font(.system(size: 24)).foregroundStyle(Theme.muted) }
                    }.frame(width: 70, height: 70).background(Theme.raised).clipShape(RoundedRectangle(cornerRadius: 4))
                    if image != nil {
                        Button { image = nil; error = nil } label: {
                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Theme.panel).font(.system(size: 16))
                        }.buttonStyle(.plain).accessibilityLabel("Remove part image")
                    }
                }
                ToolButton(symbol: "photo.badge.plus", title: "Import image from file") { importFile() }
                ToolButton(symbol: "doc.on.clipboard", title: "Paste image from clipboard") { pasteImage() }
                Spacer(minLength: 0)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.prompt = "Import image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do { image = try draft.importImage(from: url); error = nil } catch { self.error = error.localizedDescription }
    }
    private func pasteImage() {
        do {
            let pasteboard = NSPasteboard.general
            if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation {
                image = try draft.importImage(data: data)
            } else if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
                image = try draft.importImage(from: url)
            } else { throw InventoryError.message("Copy an image or image file to the clipboard first.") }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
