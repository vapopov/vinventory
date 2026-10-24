import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decode scaled, orientation-correct versions without loading a full-size bitmap.
enum ImagePreviews {
    static func write(from source: CGImageSource, maxPixels: Int, to target: URL) throws {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary),
              let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw InventoryError.message("Cannot create the image preview.")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw InventoryError.message("Cannot save the image preview.") }
    }
    static func write(from original: URL, maxPixels: Int, to target: URL) throws {
        guard let source = CGImageSourceCreateWithURL(original as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw InventoryError.message("Cannot read the original image.")
        }
        try write(from: source, maxPixels: maxPixels, to: target)
    }
}
