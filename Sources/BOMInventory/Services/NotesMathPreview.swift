import AppKit

/// Only generated markup reaches the web view: note text is always escaped.
enum NotesMathPreview {
    static var pageURL: URL? {
        if let root = Bundle.main.resourceURL {
            let page = root.appendingPathComponent("BOMInventory_BOMInventory.bundle/KaTeX/notes-preview.html")
            if FileManager.default.fileExists(atPath: page.path) { return page }
        }
        return Bundle.module.url(forResource: "notes-preview", withExtension: "html", subdirectory: "KaTeX")
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func html(_ text: NSAttributedString) -> String {
        var html = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                let image = (attachment.attachmentCell as? NSTextAttachmentCell)?.image ?? attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
                if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
                    html += "<img alt=\"Note image\" src=\"data:image/png;base64,\(data.base64EncodedString())\">"
                }
                return
            }
            var style = ""
            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) { style += "font-weight:bold;" }
                if traits.contains(.italicFontMask) { style += "font-style:italic;" }
            }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { style += "text-decoration:underline;" }
            let value = escape((text.string as NSString).substring(with: range))
            html += style.isEmpty ? value : "<span style=\"\(style)\">\(value)</span>"
        }
        return html
    }
}
