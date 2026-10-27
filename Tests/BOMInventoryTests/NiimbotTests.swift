import XCTest
import AppKit
import CoreImage
@testable import BOMInventory

final class NiimbotTests: XCTestCase {
    func testPacketFramingChecksumAndStreamingDecoder() throws {
        let frame = NiimbotFrame(command: 0x21, payload: [3])
        XCTAssertEqual(try frame.encoded(), Data([0x55, 0x55, 0x21, 1, 3, 0x23, 0xaa, 0xaa]))
        var decoder = NiimbotFrameDecoder()
        let encoded = try frame.encoded()
        XCTAssertTrue(decoder.append(Data([0, 0x55]) + encoded.prefix(3)).isEmpty)
        let decoded = decoder.append(encoded.dropFirst(3) + encoded)
        XCTAssertEqual(decoded, [frame, frame])
        var corrupt = Array(encoded); corrupt[5] ^= 1
        XCTAssertEqual(decoder.append(Data(corrupt) + encoded), [frame])
        XCTAssertThrowsError(try NiimbotFrame(command: 0, payload: Array(repeating: 0, count: 256)).encoded())
    }
    func testRowEncodingUsesTotalBitCountAndRunLengthLimit() throws {
        let raster = NiimbotRaster(width: 16, height: 3, bytes: [0, 0, 0x80, 0x01, 0x80, 0x01])
        let frames = try raster.rowFrames()
        XCTAssertEqual(frames, [NiimbotFrame(command: 0x84, payload: [0, 0, 1]), NiimbotFrame(command: 0x85, payload: [0, 1, 0, 2, 0, 2, 0x80, 0x01])])
        let blank = NiimbotRaster(width: 8, height: 401, bytes: Array(repeating: 0, count: 401))
        XCTAssertEqual(try blank.rowFrames().map(\.payload), [[0, 0, 200], [0, 200, 200], [1, 144, 1]])
        let black = NiimbotRaster(width: 384, height: 1, bytes: Array(repeating: 255, count: 48))
        XCTAssertEqual(Array(try black.rowFrames()[0].payload.prefix(6)), [0, 0, 0, 128, 1, 1])
        XCTAssertThrowsError(try NiimbotRaster(width: 384, height: 240, bytes: []).rowFrames())
    }
    func testB1PageDimensionsAndCopyCount() throws {
        XCTAssertEqual(try NiimbotRaster.pageSize(copies: 2), [0, 240, 1, 128, 0, 2])
        XCTAssertThrowsError(try NiimbotRaster.pageSize(copies: 0))
        XCTAssertThrowsError(try NiimbotRaster.pageSize(copies: 21))
    }
    @MainActor func testMonochromePackingAndPaperOffset() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 9, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let rgba = try XCTUnwrap(bitmap.bitmapData)
        for i in 0..<(bitmap.bytesPerRow * 2) { rgba[i] = 255 }
        for x in [0, 8] { for channel in 0..<3 { rgba[x * 4 + channel] = 0 } }
        XCTAssertEqual(try NiimbotRaster.packed(bitmap).bytes, [0x80, 0x80, 0, 0])
        XCTAssertEqual(try NiimbotRaster.packed(bitmap, offsetY: 1).bytes, [0, 0, 0x80, 0x80])
    }
    @MainActor func testNativeB1LabelHasDecodableQRAndValidPackets() throws {
        var part = Part(); part.number = "RC0402FR-07200KL"; part.manufacturer = "YAGEO"; part.stock = 100
        part.description = "200kΩ 62.5mW 50V Thick Film Resistor ±1% 0402 Chip Resistor"
        let bitmap = try BarcodeLabel.bitmap(for: part, pixelWidth: 384, pixelHeight: 240)
        XCTAssertEqual(bitmap.pixelsWide, 384); XCTAssertEqual(bitmap.pixelsHigh, 240)
        let raster = try NiimbotRaster.label(for: part)
        XCTAssertEqual(raster.bytes.count, 48 * 240)
        XCTAssertTrue(raster.bytes.contains { $0 != 0 })
        let frames = try raster.rowFrames()
        var decoder = NiimbotFrameDecoder()
        for frame in frames { XCTAssertEqual(decoder.append(try frame.encoded()), [frame]) }
        // Decode the actual thresholded printer raster, rather than the source image.
        let monochrome = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 384, pixelsHigh: 240, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let rgba = try XCTUnwrap(monochrome.bitmapData)
        for y in 0..<240 { for x in 0..<384 {
            let black = raster.bytes[y * 48 + x / 8] & UInt8(0x80 >> (x % 8)) != 0
            let base = y * monochrome.bytesPerRow + x * 4
            for channel in 0..<3 { rgba[base + channel] = black ? 0 : 255 }
            rgba[base + 3] = 255
        } }
        let cg = try XCTUnwrap(monochrome.cgImage)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 384, 240, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        CIContext().render(CIImage(cgImage: cg), to: frame)
        XCTAssertEqual(try BarcodeCamera.detectBarcode(in: frame), part.barcode)
        if let path = ProcessInfo.processInfo.environment["NIIMBOT_PREVIEW_PATH"] { try monochrome.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
    }
}
