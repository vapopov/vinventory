import AppKit

struct NotesVisualToken: Codable {
    var kind: String
    var value: String
    var bold: Bool? = nil
    var italic: Bool? = nil
    var underline: Bool? = nil
    var display: Bool? = nil
}

/// Visual math is saved as editable LaTeX, using the existing RTF/image storage.
enum NotesVisualDocument {
    static func attributedString(_ tokens: [NotesVisualToken]) throws -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for token in tokens {
            var font = NSFont.systemFont(ofSize: 14)
            if token.bold == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if token.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
            if token.underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            switch token.kind {
            case "text": result.append(NSAttributedString(string: token.value, attributes: attributes))
            case "math":
                let value = token.display == true ? "\\[\(token.value)\\]" : "\\(\(token.value)\\)"
                result.append(NSAttributedString(string: value, attributes: attributes))
            case "image":
                guard token.value.hasPrefix("data:image/"), let comma = token.value.firstIndex(of: ","), token.value[..<comma].hasSuffix(";base64"),
                      let data = Data(base64Encoded: String(token.value[token.value.index(after: comma)...])), let image = NSImage(data: data), let tiff = image.tiffRepresentation else {
                    throw InventoryError.message("Unable to save a pasted image.")
                }
                let wrapper = FileWrapper(regularFileWithContents: tiff)
                wrapper.preferredFilename = UUID().uuidString + ".tiff"
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                let scale = min(1, 700 / max(1, image.size.width))
                image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                result.append(NSAttributedString(attachment: attachment))
            default: throw InventoryError.message("Unsupported note content.")
            }
        }
        return result
    }
    static var pageURL: URL? {
        if let root = Bundle.main.resourceURL {
            let page = root.appendingPathComponent("BOMInventory_BOMInventory.bundle/KaTeX/notes-editor.html")
            if FileManager.default.fileExists(atPath: page.path) { return page }
        }
        return Bundle.module.url(forResource: "notes-editor", withExtension: "html", subdirectory: "KaTeX")
    }
}
