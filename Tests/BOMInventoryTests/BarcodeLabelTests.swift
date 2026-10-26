import XCTest
import AppKit
import PDFKit
@testable import BOMInventory

final class BarcodeLabelTests: XCTestCase {
    @MainActor func testFullPartNumberAndDescriptionAreNotTruncated() throws {
        var part = Part()
        part.number = "RC0402FR-07200KL"
        part.manufacturer = "YAGEO"
        part.stock = 100
        part.value = "200kΩ"; part.tolerance = "±1%"; part.package = "0402"
        part.description = "200kΩ 62.5mW 50V Thick Film Resistor ±100ppm/℃ ±1% 0402 Chip Resistor - Surface Mount RoHS"
        let data = try BarcodeLabel.data(for: part, pdf: true)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = try XCTUnwrap(pdf.string)
        func compact(_ value: String) -> String { value.filter { !$0.isWhitespace } }
        XCTAssertTrue(text.contains(part.number), "Part number must remain on one line: \(text)")
        XCTAssertTrue(compact(text).contains(compact(part.description)), text)
        XCTAssertFalse(text.contains("…"))
        XCTAssertTrue(text.contains("Qty: 100"), text)
        if let path = ProcessInfo.processInfo.environment["BARCODE_LABEL_PREVIEW_PATH"] {
            try BarcodeLabel.data(for: part, pdf: false).write(to: URL(fileURLWithPath: path))
        }
    }
    @MainActor func testPrinterLabelDimensions() throws {
        var part = Part(); part.number = "RC0402FR-074K7L"; part.description = "4.7kΩ ±1% 62.5mW 0402 Thick Film Resistor"
        let pdf = try XCTUnwrap(PDFDocument(data: BarcodeLabel.data(for: part, pdf: true)))
        let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 50 * 72 / 25.4, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 30 * 72 / 25.4, accuracy: 0.01)
        let png = try XCTUnwrap(NSBitmapImageRep(data: BarcodeLabel.data(for: part, pdf: false)))
        XCTAssertEqual(png.pixelsWide, 591)
        XCTAssertEqual(png.pixelsHigh, 354)
    }
}
