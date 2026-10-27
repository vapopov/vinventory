import Foundation

struct PreparedAttachments {
    var part: Part
    var createdFolders: [URL]
    func rollback() {
        for folder in createdFolders {
            try? FileManager.default.removeItem(at: folder)
            let parent = folder.deletingLastPathComponent()
            if (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true { try? FileManager.default.removeItem(at: parent) }
        }
    }
}
/// Only files beneath this managed root may be removed. Source files are always copied.
struct AttachmentStorage {
    let root: URL
    private func folder(for partID: String) throws -> URL {
        guard !partID.isEmpty, !partID.contains("/"), partID != ".", partID != ".." else { throw InventoryError.message("Invalid part identifier for attachments.") }
        let folder = root.appendingPathComponent(partID, isDirectory: true)
        guard folder.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/") else {
            throw InventoryError.message("The attachment folder must stay inside the inventory's local storage.")
        }
        return folder
    }
    private func owns(_ path: String, partID: String) throws -> Bool {
        let owner = try folder(for: partID).resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(owner)
    }
    func prepare(_ part: Part) throws -> PreparedAttachments {
        var result = PreparedAttachments(part: part, createdFolders: [])
        func newFolder() throws -> URL {
            let directory = try folder(for: part.id).appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            result.createdFolders.append(directory)
            return directory
        }
        do {
            if let image = part.image, !(try image.previewPath != nil && image.paths.allSatisfy { try owns($0, partID: part.id) }) {
                let directory = try newFolder()
                let original = directory.appendingPathComponent(URL(fileURLWithPath: image.originalPath).lastPathComponent)
                let thumbnail = directory.appendingPathComponent("thumbnail.png")
                let preview = directory.appendingPathComponent("preview.png")
                guard original != thumbnail && original != preview else { throw InventoryError.message("Invalid original image filename.") }
                try FileManager.default.copyItem(atPath: image.originalPath, toPath: original.path)
                try FileManager.default.copyItem(atPath: image.thumbnailPath, toPath: thumbnail.path)
                if let existingPreview = image.previewPath, FileManager.default.fileExists(atPath: existingPreview) {
                    try FileManager.default.copyItem(atPath: existingPreview, toPath: preview.path)
                } else { try ImagePreviews.write(from: original, maxPixels: 800, to: preview) }
                result.part.image = PartImage(originalPath: original.path, thumbnailPath: thumbnail.path, previewPath: preview.path)
            }
            for (name, path) in part.notes.images where try !owns(path, partID: part.id) {
                let target = try newFolder().appendingPathComponent(UUID().uuidString + "-" + URL(fileURLWithPath: path).lastPathComponent)
                try FileManager.default.copyItem(atPath: path, toPath: target.path)
                result.part.notes.images[name] = target.path
            }
            if !part.datasheet.isEmpty {
                let source = try DatasheetReference.url(for: part.datasheet)
                if source.isFileURL {
                    try DatasheetReference.validatePDF(at: source)
                    if try !owns(source.path, partID: part.id) {
                        let target = try newFolder().appendingPathComponent("datasheet.pdf")
                        try FileManager.default.copyItem(at: source, to: target)
                        result.part.datasheet = target.path
                    } else { result.part.datasheet = source.path }
                }
            }
            return result
        } catch { result.rollback(); throw error }
    }
    /// Upgrade existing two-file images in place while keeping their original untouched.
    func ensurePreview(for part: Part) throws -> Part {
        guard let image = part.image, try owns(image.originalPath, partID: part.id), FileManager.default.fileExists(atPath: image.originalPath) else { return part }
        if let path = image.previewPath, FileManager.default.fileExists(atPath: path) { return part }
        let target = URL(fileURLWithPath: image.originalPath).deletingLastPathComponent().appendingPathComponent("preview.png")
        try ImagePreviews.write(from: URL(fileURLWithPath: image.originalPath), maxPixels: 800, to: target)
        var updated = part
        updated.image?.previewPath = target.path
        return updated
    }
    func removeReplaced(previous: Part?, current: Part) throws {
        guard let previous else { return }
        var paths: [String] = []
        if previous.image != current.image, let image = previous.image { paths += image.paths.filter { !(current.image?.paths.contains($0) ?? false) } }
        if previous.datasheet != current.datasheet, let oldURL = try? DatasheetReference.url(for: previous.datasheet), oldURL.isFileURL { paths.append(oldURL.path) }
        paths += previous.notes.images.values.filter { !current.notes.images.values.contains($0) }
        for path in paths where try owns(path, partID: previous.id) {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            if (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true { try FileManager.default.removeItem(at: parent) }
        }
    }
    func removePart(_ id: String) throws {
        let directory = try folder(for: id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
