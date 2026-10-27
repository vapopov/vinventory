import AppKit

@MainActor extension NiimbotRaster {
    static func label(for part: Part) throws -> NiimbotRaster {
        // Render at native B1 resolution; do not downsample the 300 dpi PNG.
        let bitmap = try BarcodeLabel.bitmap(for: part, pixelWidth: b1Width, pixelHeight: b1Height)
        return try packed(bitmap, offsetY: 4)
    }
    static func packed(_ bitmap: NSBitmapImageRep, offsetY: Int = 0) throws -> NiimbotRaster {
        guard bitmap.pixelsWide > 0, bitmap.pixelsWide <= b1Width, bitmap.pixelsHigh > 0, bitmap.pixelsHigh <= 65535 else { throw InventoryError.message("Invalid printer bitmap dimensions.") }
        guard bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 4, !bitmap.isPlanar,
              !bitmap.bitmapFormat.contains(.alphaFirst), let rgba = bitmap.bitmapData else { throw InventoryError.message("Expected an RGBA printer bitmap.") }
        let stride = (bitmap.pixelsWide + 7) / 8
        var pixels = [UInt8](repeating: 0, count: stride * bitmap.pixelsHigh)
        for y in 0..<bitmap.pixelsHigh {
            let sourceY = y - offsetY
            guard (0..<bitmap.pixelsHigh).contains(sourceY) else { continue }
            for x in 0..<bitmap.pixelsWide {
                let base = sourceY * bitmap.bytesPerRow + x * 4
                let luminance = 0.299 * Double(rgba[base]) + 0.587 * Double(rgba[base + 1]) + 0.114 * Double(rgba[base + 2])
                if rgba[base + 3] > 32 && luminance < 128 { pixels[y * stride + x / 8] |= UInt8(0x80 >> (x % 8)) }
            }
        }
        return NiimbotRaster(width: bitmap.pixelsWide, height: bitmap.pixelsHigh, bytes: pixels)
    }
}
