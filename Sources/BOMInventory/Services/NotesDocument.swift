import AppKit

/// The database keeps text/formatting; RTFD images are ordinary managed attachments.
enum NotesDocument {
    static func load(_ notes: PartNotes) throws -> NSAttributedString {
        guard !notes.rtf.isEmpty else { return NSAttributedString(string: notes.text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.textColor]) }
        var files = ["TXT.rtf": FileWrapper(regularFileWithContents: notes.rtf)]
        for (name, path) in notes.images {
            guard name == URL(fileURLWithPath: name).lastPathComponent, name != "TXT.rtf" else { throw InventoryError.message("Invalid note image name.") }
            files[name] = FileWrapper(regularFileWithContents: try Data(contentsOf: URL(fileURLWithPath: path)))
        }
        guard let document = NSAttributedString(rtfdFileWrapper: FileWrapper(directoryWithFileWrappers: files), documentAttributes: nil) else { throw InventoryError.message("Unable to read this note.") }
        return document
    }
    static func save(_ document: NSAttributedString, draft: AttachmentDraft) throws -> PartNotes {
        if document.length == 0 { return PartNotes() }
        let wrapper = try document.fileWrapper(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        guard let files = wrapper.fileWrappers, let rtf = files["TXT.rtf"]?.regularFileContents else { throw InventoryError.message("Unable to save note formatting.") }
        var notes = PartNotes(text: document.string, rtf: rtf)
        let folder = draft.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, file) in files where name != "TXT.rtf" {
            guard let data = file.regularFileContents, NSImage(data: data) != nil, name == URL(fileURLWithPath: name).lastPathComponent else { throw InventoryError.message("Only image attachments are supported in notes.") }
            let target = folder.appendingPathComponent(name)
            try data.write(to: target, options: .atomic)
            notes.images[name] = target.path
        }
        return notes
    }
}
