import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DatasheetEditor: View {
    @Binding var value: String
    @Binding var downloading: Bool
    var draft: AttachmentDraft
    @State private var downloadTask: Task<Void, Never>?
    @State private var error: String?
    private var remote: Bool {
        guard let url = try? DatasheetReference.url(for: value) else { return false }
        return !url.isFileURL
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                TextField("", text: $value).accessibilityLabel("Datasheet URL or local PDF").disabled(downloading)
                ToolButton(symbol: "folder", title: "Import PDF from file") { importFile() }.disabled(downloading)
                if downloading {
                    ProgressView().controlSize(.small).frame(width: 22)
                    ToolButton(symbol: "stop.fill", title: "Cancel datasheet download") { downloadTask?.cancel() }
                } else {
                    ToolButton(symbol: "arrow.down.to.line", title: "Download URL as local PDF") { download() }.disabled(!remote)
                }
                if !value.isEmpty && !downloading {
                    Button { value = ""; error = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain).help("Remove datasheet")
                }
            }
            Text("Keep a web link, download it, or import a PDF.").font(.system(size: 10)).foregroundStyle(Theme.muted)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.accessibilityElement(children: .contain).onDisappear { downloadTask?.cancel() }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false; panel.prompt = "Import PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do { value = try draft.importPDF(from: url); error = nil } catch { self.error = error.localizedDescription }
    }
    private func download() {
        guard let source = try? DatasheetReference.url(for: value), !source.isFileURL else { return }
        let target = draft.newPDFURL()
        downloadTask = Task { @MainActor in
            downloading = true
            error = nil
            defer { downloading = false }
            do {
                try await DatasheetDownloader.download(from: source, to: target)
                try Task.checkCancellation()
                value = target.path
            } catch is CancellationError { try? FileManager.default.removeItem(at: target) }
            catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
                try? FileManager.default.removeItem(at: target)
            }
        }
    }
}
