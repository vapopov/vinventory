import AppKit
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
@MainActor enum BarcodeLabel {
    static func image(for part: Part) throws -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(part.barcode.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { throw InventoryError.message("Could not generate barcode.") }
        let image = NSImage(size: NSSize(width: 640, height: 200))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 200).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x: 14, y: 14, width: 172, height: 172))
        draw(part.number, rect: NSRect(x: 204, y: 145, width: 420, height: 40), font: .boldSystemFont(ofSize: 23))
        draw(part.manufacturer, rect: NSRect(x: 204, y: 113, width: 420, height: 28), font: .systemFont(ofSize: 17))
        draw(part.description, rect: NSRect(x: 204, y: 43, width: 420, height: 65), font: .systemFont(ofSize: 16))
        draw(part.barcode, rect: NSRect(x: 204, y: 13, width: 420, height: 24), font: .monospacedSystemFont(ofSize: 10, weight: .regular))
        image.unlockFocus()
        return image
    }
    private static func draw(_ string: String, rect: NSRect, font: NSFont) { (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: NSColor.black]) }
    static func export(_ part: Part, pdf: Bool) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [pdf ? .pdf : .png]
        panel.nameFieldStringValue = "\(part.number.replacingOccurrences(of: "/", with: "-"))-label.\(pdf ? "pdf" : "png")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data(for: part, pdf: pdf).write(to: url)
    }
    static func data(for part: Part, pdf: Bool) throws -> Data {
        let image = try image(for: part)
        if pdf {
            let view = NSImageView(frame: NSRect(origin: .zero, size: image.size)); view.image = image
            return view.dataWithPDF(inside: view.bounds)
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw InventoryError.message("Could not encode PNG.") }
        return png
    }
    static func copy(_ part: Part) throws { let image = try image(for: part); NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) }
}
