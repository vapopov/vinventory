import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Each editor owns a private temporary directory. Imports never mutate saved assets.
final class AttachmentDraft {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BOMInventory-Draft-\(UUID().uuidString)", isDirectory: true)
    func newPDFURL() -> URL { directory.appendingPathComponent("\(UUID().uuidString).pdf") }
    func importPDF(from source: URL) throws -> String {
        try DatasheetReference.validatePDF(at: source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = newPDFURL()
        try FileManager.default.copyItem(at: source, to: target)
        return target.path
    }
    func importImage(from source: URL) throws -> PartImage { try importImage(data: Data(contentsOf: source)) }
    func importImage(data: Data) throws -> PartImage {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(image) else {
            throw InventoryError.message("Choose a supported image file or copy an image to the clipboard.")
        }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let original = folder.appendingPathComponent("original.\(UTType(type as String)?.preferredFilenameExtension ?? "image")")
            let resized = folder.appendingPathComponent("thumbnail.png")
            try data.write(to: original, options: .atomic)
            let preview = folder.appendingPathComponent("preview.png")
            try ImagePreviews.write(from: image, maxPixels: 160, to: resized)
            try ImagePreviews.write(from: image, maxPixels: 800, to: preview)
            return PartImage(originalPath: original.path, thumbnailPath: resized.path, previewPath: preview.path)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    func discard() { try? FileManager.default.removeItem(at: directory) }
    deinit { discard() }
}
