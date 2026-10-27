import AppKit
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
@MainActor enum BarcodeLabel {
    static let labelSize = NSSize(width: 50 * 72 / 25.4, height: 30 * 72 / 25.4)
    static let dpi = 300.0

    static func image(for part: Part) throws -> NSImage {
        let bitmap = try bitmap(for: part)
        let image = NSImage(size: labelSize)
        image.addRepresentation(bitmap)
        return image
    }
    static func bitmap(for part: Part, pixelWidth: Int? = nil, pixelHeight: Int? = nil) throws -> NSBitmapImageRep {
        let width = pixelWidth ?? Int((labelSize.width * dpi / 72).rounded())
        let height = pixelHeight ?? Int((labelSize.height * dpi / 72).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw InventoryError.message("Could not create label image.") }
        bitmap.size = labelSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.cgContext.scaleBy(x: CGFloat(width) / labelSize.width, y: CGFloat(height) / labelSize.height)
        try render(part, pixelScale: CGFloat(width) / labelSize.width)
        return bitmap
    }
    private static func render(_ part: Part, pixelScale: CGFloat? = nil) throws {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(part.barcode.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { throw InventoryError.message("Could not generate barcode.") }
        NSColor.white.setFill()
        NSRect(origin: .zero, size: labelSize).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        draw(part.number, rect: NSRect(x: 4, y: 69, width: labelSize.width - 8, height: 13), font: .boldSystemFont(ofSize: 10), singleLine: true)
        // Keep whole QR modules on printer pixels, with a white quiet zone.
        var qrSize: CGFloat = 42
        if let pixelScale { qrSize = floor(qrSize * pixelScale / CGFloat(cg.width)) * CGFloat(cg.width) / pixelScale }
        let qrX = pixelScale.map { (5 * $0).rounded() / $0 } ?? 5
        let qrY = pixelScale.map { (18 * $0).rounded() / $0 } ?? 18
        NSImage(cgImage: cg, size: .zero).draw(in: NSRect(x: qrX, y: qrY, width: qrSize, height: qrSize))
        let textX: CGFloat = 53
        let textWidth = labelSize.width - textX - 4
        draw(part.manufacturer, rect: NSRect(x: textX, y: 54, width: textWidth, height: 12), font: .systemFont(ofSize: 7.5, weight: .medium))
        let specs = [part.value, part.tolerance, part.package].filter { !$0.isEmpty }.joined(separator: " • ")
        draw(specs, rect: NSRect(x: textX, y: 42, width: textWidth, height: 11), font: .boldSystemFont(ofSize: 7))
        draw(part.description, rect: NSRect(x: textX, y: 13, width: textWidth, height: 28), font: .systemFont(ofSize: 7, weight: .medium))
        draw("Qty: \(part.stock)", rect: NSRect(x: textX, y: 2, width: textWidth, height: 11), font: .boldSystemFont(ofSize: 8), singleLine: true)
    }

    private static func draw(_ string: String, rect: NSRect, font: NSFont, singleLine: Bool = false) {
        guard !string.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = singleLine ? .byClipping : .byWordWrapping
        var fittedFont = font
        func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
        }
        if singleLine {
            let text = string.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            let width = (text as NSString).size(withAttributes: attributes(font)).width
            if width > rect.width {
                fittedFont = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * (rect.width - 1) / width) ?? font
            }
            (text as NSString).draw(at: NSPoint(x: rect.minX, y: rect.maxY - fittedFont.ascender - 2), withAttributes: attributes(fittedFont))
            return
        }
        // Measure all lines, rather than truncating the final visible line.
        // Long descriptions use smaller type; short descriptions keep the preferred size.
        while fittedFont.pointSize > 0.5 {
            let measured = (string as NSString).boundingRect(with: NSSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(fittedFont))
            if ceil(measured.height) + ceil(fittedFont.pointSize * 0.6) <= rect.height && ceil(measured.width) <= rect.width { break }
            fittedFont = NSFont(descriptor: font.fontDescriptor, size: fittedFont.pointSize - 0.25) ?? font
        }
        (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(fittedFont))
    }
    static func export(_ part: Part, pdf: Bool) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [pdf ? .pdf : .png]
        panel.nameFieldStringValue = "\(part.number.replacingOccurrences(of: "/", with: "-"))-label.\(pdf ? "pdf" : "png")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data(for: part, pdf: pdf).write(to: url)
    }
    static func data(for part: Part, pdf: Bool) throws -> Data {
        if pdf {
            let data = NSMutableData()
            var bounds = CGRect(origin: .zero, size: labelSize)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw InventoryError.message("Could not create label PDF.") }
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            defer { NSGraphicsContext.restoreGraphicsState() }
            try render(part)
            context.endPDFPage(); context.closePDF()
            return data as Data
        }
        guard let png = try bitmap(for: part).representation(using: .png, properties: [:]) else { throw InventoryError.message("Could not encode PNG.") }
        return png
    }
    static func copy(_ part: Part) throws { let image = try image(for: part); NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) }
}
