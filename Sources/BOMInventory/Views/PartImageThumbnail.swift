import SwiftUI
import AppKit

struct PartImageThumbnail: View {
    var image: PartImage?
    var partNumber: String
    @State private var showingPreview = false
    var body: some View {
        if let image, let thumbnail = NSImage(contentsOfFile: image.thumbnailPath) {
            Button {
                showingPreview = false
                NSWorkspace.shared.open(URL(fileURLWithPath: image.originalPath))
            } label: {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 70, height: 70).background(Theme.raised)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open original image for \(partNumber)")
            .onHover { showingPreview = $0 }
            .popover(isPresented: $showingPreview, arrowEdge: .leading) {
                VStack(spacing: 10) {
                    if let preview = NSImage(contentsOfFile: image.previewPath ?? image.thumbnailPath) {
                        Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).frame(width: 360, height: 300)
                    }
                    Text(partNumber).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                }.padding(12).background(Theme.panel)
            }
            .accessibilityAction(named: "Show image preview") { showingPreview = true }
            .onChange(of: image.originalPath) { _, _ in showingPreview = false }
            .onDisappear { showingPreview = false }
        } else {
            Image(systemName: "cpu").font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(Theme.muted.opacity(0.5)).frame(width: 70, height: 70).background(Theme.raised)
        }
    }
}
