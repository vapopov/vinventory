import XCTest
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import BOMInventory

final class BarcodeCameraTests: XCTestCase {
    func testSavedCameraSelectionAndFallback() {
        XCTAssertEqual(BarcodeCamera.resolvedCameraID(preferred: "usb", available: ["built-in", "usb"], defaultID: "built-in"), "usb")
        XCTAssertEqual(BarcodeCamera.resolvedCameraID(preferred: "missing", available: ["usb", "built-in"], defaultID: "built-in"), "built-in")
        XCTAssertEqual(BarcodeCamera.resolvedCameraID(preferred: "missing", available: ["usb"], defaultID: nil), "usb")
        XCTAssertNil(BarcodeCamera.resolvedCameraID(preferred: "usb", available: [], defaultID: nil))
    }
    func testRecognizesInventoryQRFromCameraFrame() throws {
        let payload = UUID().uuidString
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        let qr = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let canvas = CGRect(x: 0, y: 0, width: 512, height: 512)
        let image = qr.transformed(by: CGAffineTransform(translationX: 60, y: 60)).composited(over: CIImage(color: .white).cropped(to: canvas))
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 512, 512, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        CIContext().render(image, to: frame)
        XCTAssertEqual(try BarcodeCamera.detectBarcode(in: frame), payload)
    }
}
