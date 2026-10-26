import XCTest
import AppKit
import ImageIO
@testable import BOMInventory

final class AttachmentTests: XCTestCase {
    private func imageData(width: Int = 640, height: Int = 320) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
    @MainActor func testPurchaseAPIImageImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"), attachmentStorage: AttachmentStorage(root: root))
        let router = InventoryAPIRouter(store: store)
        let body: [String: Any] = ["part": ["number": "LCSC test", "datasheet": "https://example.com/part.pdf"], "quantity": 2, "imageBase64": try imageData().base64EncodedString()]
        let response = router.handle(method: "POST", target: "/v1/purchases", body: try JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(response.status, 201, String(data: response.data, encoding: .utf8) ?? "")
        let item = try XCTUnwrap(store.purchases.first)
        XCTAssertEqual(item.part.datasheet, "https://example.com/part.pdf")
        let image = try XCTUnwrap(item.part.image)
        for path in image.paths { XCTAssertTrue(FileManager.default.fileExists(atPath: path)); XCTAssertTrue(path.hasPrefix(root.path)) }
        var invalid = body; invalid["imageBase64"] = Data("invalid image".utf8).base64EncodedString()
        XCTAssertEqual(router.handle(method: "POST", target: "/v1/purchases", body: try JSONSerialization.data(withJSONObject: invalid)).status, 400)
        XCTAssertEqual(store.purchases.count, 1)
    }
    @MainActor func testAttachmentImportReplacementRemovalAndPartDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourcePDF = root.appendingPathComponent("source.pdf")
        let pdfData = try BarcodeLabel.data(for: Part(), pdf: true)
        try pdfData.write(to: sourcePDF)
        let originalData = try imageData()
        let draft = AttachmentDraft()
        defer { draft.discard() }
        var part = Part(); part.number = "L1"
        part.image = try draft.importImage(data: originalData)
        part.datasheet = try draft.importPDF(from: sourcePDF)
        let previewPath = try XCTUnwrap(part.image?.thumbnailPath)
        let previewSource = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: previewPath) as CFURL, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
        XCTAssertEqual(preview.width, 160)
        XCTAssertEqual(preview.height, 80)
        let assets = AttachmentStorage(root: root.appendingPathComponent("Attachments"))
        let repository = try SQLiteRepository(path: ":memory:")
        let store = InventoryStore(repository: repository, attachmentStorage: assets)
        try store.save(part)
        part = try XCTUnwrap(store.parts.first)
        let firstImage = try XCTUnwrap(part.image)
        let firstPDF = part.datasheet
        let firstPreview = try XCTUnwrap(firstImage.previewPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstPreview))
        let bigSource = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: firstPreview) as CFURL, nil))
        let bigPreview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(bigSource, 0, nil))
        XCTAssertEqual(bigPreview.width, 640)
        XCTAssertEqual(bigPreview.height, 320)
        XCTAssertTrue(firstImage.originalPath.hasPrefix(assets.root.path))
        XCTAssertTrue(firstPDF.hasPrefix(assets.root.path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstImage.originalPath)), originalData)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPDF)), pdfData)
        draft.discard()
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstImage.thumbnailPath))
        XCTAssertEqual(try repository.loadParts().first?.image, firstImage)
        let replacement = AttachmentDraft()
        defer { replacement.discard() }
        part.image = try replacement.importImage(data: originalData)
        part.datasheet = "https://example.com/datasheet.pdf"
        try store.save(part)
        part = try XCTUnwrap(store.parts.first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstImage.originalPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstImage.thumbnailPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstPDF))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstPreview))
        let replacementImage = try XCTUnwrap(part.image)
        part.image = nil
        try store.save(part)
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementImage.originalPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementImage.thumbnailPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(replacementImage.previewPath)))
        part.image = try replacement.importImage(data: originalData)
        part.datasheet = try replacement.importPDF(from: sourcePDF)
        try store.save(part)
        part = try XCTUnwrap(store.parts.first)
        try store.delete(part)
        XCTAssertFalse(FileManager.default.fileExists(atPath: assets.root.appendingPathComponent(part.id).path))
        XCTAssertEqual(try Data(contentsOf: sourcePDF), pdfData, "Original source files must never be deleted")
    }
    @MainActor func testLegacyImagesGainLargePreviewOnReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = AttachmentDraft()
        defer { draft.discard() }
        let original = try imageData(width: 1600, height: 800)
        var part = Part(); part.number = "Legacy image"; part.image = try draft.importImage(data: original)
        let assets = AttachmentStorage(root: root)
        let prepared = try assets.prepare(part)
        part = prepared.part
        let preview = try XCTUnwrap(part.image?.previewPath)
        try FileManager.default.removeItem(atPath: preview)
        part.image?.previewPath = nil
        let repository = try SQLiteRepository(path: ":memory:")
        try repository.save(part)
        let oldJSON = try JSONEncoder().encode(part)
        XCTAssertNil(try JSONDecoder().decode(Part.self, from: oldJSON).image?.previewPath)
        let store = InventoryStore(repository: repository, attachmentStorage: assets)
        XCTAssertNil(store.error)
        let upgraded = try XCTUnwrap(store.parts.first?.image)
        let large = try XCTUnwrap(upgraded.previewPath)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: large) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 800)
        XCTAssertEqual(image.height, 400)
        XCTAssertEqual(upgraded.originalPath, part.image?.originalPath)
        XCTAssertEqual(upgraded.thumbnailPath, part.image?.thumbnailPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: upgraded.originalPath)), original)
        XCTAssertEqual(try repository.loadParts().first?.image, upgraded)
    }
    func testLiveTIDownloadWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["BOM_INVENTORY_LIVE_DOWNLOAD_TEST"] == "1" else {
            throw XCTSkip("Set BOM_INVENTORY_LIVE_DOWNLOAD_TEST=1 to verify the vendor URL over the network")
        }
        let draft = AttachmentDraft()
        defer { draft.discard() }
        let target = draft.newPDFURL()
        try await DatasheetDownloader.download(from: URL(string: "http://www.ti.com/lit/ds/symlink/tps62823.pdf")!, to: target)
        try DatasheetReference.validatePDF(at: target)
        XCTAssertGreaterThan(try Data(contentsOf: target).count, 1000)
    }
    @MainActor func testFailedDatabaseSaveRollsBackNewFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = AttachmentStorage(root: root)
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"), attachmentStorage: assets)
        var existing = Part(); existing.number = "Existing"
        try store.save(existing)
        let draft = AttachmentDraft()
        defer { draft.discard() }
        var duplicate = Part(); duplicate.number = "Duplicate"; duplicate.barcode = existing.barcode
        duplicate.image = try draft.importImage(data: imageData())
        XCTAssertThrowsError(try store.save(duplicate))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(duplicate.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(duplicate.image?.originalPath)))
        XCTAssertEqual(store.parts.count, 1)
    }
    func testInvalidImportsAndDiscardedDraft() throws {
        let draft = AttachmentDraft()
        let image = try draft.importImage(data: imageData())
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.originalPath))
        XCTAssertThrowsError(try draft.importImage(data: Data("Not an image".utf8)))
        XCTAssertThrowsError(try DatasheetReference.validatePDF(data: Data("Not a PDF".utf8)))
        draft.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.directory.path))
        XCTAssertThrowsError(try DatasheetReference.url(for: "javascript:alert(1)"))
        XCTAssertTrue(try DatasheetReference.url(for: "/tmp/datasheet.pdf").isFileURL)
        XCTAssertTrue(try DatasheetReference.url(for: "file:///tmp/datasheet.pdf").isFileURL)
        XCTAssertFalse(try DatasheetReference.url(for: "https://example.com/data.pdf").isFileURL)
    }
    @MainActor func testDatasheetDownloadValidatesResponseAndPDF() async throws {
        let draft = AttachmentDraft()
        defer { draft.discard() }
        let pdf = try BarcodeLabel.data(for: Part(), pdf: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DatasheetStubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-PDF": pdf.base64EncodedString()]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let source = URL(string: "http://example.com/datasheet.pdf")!
        let target = draft.newPDFURL()
        try await DatasheetDownloader.download(from: source, to: target, session: session)
        XCTAssertEqual(try Data(contentsOf: target), pdf)
        let invalid = draft.newPDFURL()
        do { try await DatasheetDownloader.download(from: URL(string: "https://example.com/invalid")!, to: invalid, session: session); XCTFail("HTML response accepted") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalid.path))
        let missing = draft.newPDFURL()
        do { try await DatasheetDownloader.download(from: URL(string: "https://example.com/missing")!, to: missing, session: session); XCTFail("404 accepted") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let cancelled = Task { try await DatasheetDownloader.download(from: source, to: draft.newPDFURL(), session: session) }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Cancelled download succeeded") } catch {}
    }
}
private final class DatasheetStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url!.path == "/missing" ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // HTTP input must have been upgraded before it reaches URLSession.
        guard request.url?.scheme == "https" else {
            client?.urlProtocol(self, didFailWithError: URLError(.appTransportSecurityRequiresSecureConnection))
            return
        }
        let data = request.url!.path == "/invalid" ? Data("<html>Not a PDF</html>".utf8) : Data(base64Encoded: request.value(forHTTPHeaderField: "X-Test-PDF") ?? "") ?? Data()
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
