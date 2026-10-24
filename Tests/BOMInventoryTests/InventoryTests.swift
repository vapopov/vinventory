import XCTest
import AppKit
import CoreImage
import PDFKit
import CSQLite
@testable import BOMInventory
final class InventoryTests: XCTestCase {
    @MainActor func testPersistenceMixedSearchAndAllocations() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var part = Part(); part.number = "24AA01T-I/OT"; part.description = "Serial EEPROM memory"; part.package = "SOT-23"; part.value = "1 kb"; part.stock = 100
        try store.save(part)
        XCTAssertEqual(store.search("EEPROM SOT-23 1 kb").count, 1)
        XCTAssertEqual(store.search(part.barcode).first?.id, part.id)
        try store.allocate(part, project: "Controller board", quantity: 30)
        XCTAssertEqual(store.available(part), 70)
        XCTAssertThrowsError(try store.allocate(part, project: "Overdraw", quantity: 71))
        part.stock = 29
        XCTAssertThrowsError(try store.save(part))
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.parts.first?.stock, 100)
        XCTAssertEqual(reopened.allocations.first?.quantity, 30)
        try reopened.release(reopened.allocations[0])
        XCTAssertEqual(reopened.available(reopened.parts[0]), 100)
        try reopened.delete(reopened.parts[0])
        XCTAssertTrue(reopened.parts.isEmpty)
    }
    @MainActor func testBarcodeExportAndDecode() throws {
        var part = Part(); part.number = "46333C"; part.manufacturer = "Murata"; part.description = "33 uH shielded power inductor"
        let png = try BarcodeLabel.data(for: part, pdf: false)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let cg = try XCTUnwrap(bitmap.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let codes = detector.features(in: CIImage(cgImage: cg)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(codes, [part.barcode])
        let pdf = try XCTUnwrap(PDFDocument(data: BarcodeLabel.data(for: part, pdf: true)))
        XCTAssertEqual(pdf.pageCount, 1)
    }
    @MainActor func testLabelCatalogRecencyAndSuggestions() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var saved: [Part] = []
        for index in 1...12 {
            var part = Part(); part.number = "P\(index)"; part.labels = ["Label \(index)"]
            try store.save(part)
            saved.append(part)
        }
        XCTAssertEqual(store.labelSuggestions(for: ""), (3...12).reversed().map { "Label \($0)" })
        XCTAssertEqual(try store.labelName(for: "  LABEL 1  "), "Label 1")
        try store.save(saved[0], recordFieldUse: true)
        XCTAssertEqual(store.labels.count, 12 + DescriptionAnalysis.builtInLabels.count)
        XCTAssertEqual(store.labels.first, "Label 1")
        XCTAssertEqual(store.labelSuggestions(for: "label 1", excluding: ["Label 1"]), ["Label 12", "Label 11", "Label 10"])
        XCTAssertThrowsError(try store.labelName(for: "  "))
        XCTAssertEqual(try store.labelName(for: "Draft label"), "Draft label")
        XCTAssertFalse(store.labels.contains("Draft label"), "Uncommitted labels must not enter autocomplete")
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.labels, store.labels)
        XCTAssertFalse(reopened.labels.contains("Draft label"))
    }
    @MainActor func testMultipleLabelsAndCustomToleranceRoundTrip() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        let store = InventoryStore(repository: repository)
        var seed = Part(); seed.number = "Seed"; seed.labels = ["Passive"]
        try store.save(seed)
        var part = Part(); part.number = "R1"; part.labels = ["passive", " Precision ", "Passive", "precision"]; part.tolerance = "0.1%"
        try store.save(part)
        let saved = try XCTUnwrap(store.parts.first(where: { $0.id == part.id }))
        XCTAssertEqual(saved.labels, ["Passive", "Precision"])
        XCTAssertEqual(saved.tolerance, "0.1%")
        XCTAssertEqual(store.search("precision 0.1%").first?.id, part.id)
        let recency = store.labels
        try store.save(saved)
        XCTAssertEqual(store.labels, recency, "Editing a part must not reorder recently used labels")
        part = saved; part.labels = []; part.tolerance = "5%"
        try store.save(part)
        let updated = try XCTUnwrap(repository.loadParts().first(where: { $0.id == part.id }))
        XCTAssertTrue(updated.labels.isEmpty)
        XCTAssertEqual(updated.tolerance, "5%")
        XCTAssertEqual(store.labels.filter { !DescriptionAnalysis.builtInLabels.contains($0) }, ["Passive"], "A label stays available while another part uses it")
        try store.delete(part)
        XCTAssertEqual(store.labels.filter { !DescriptionAnalysis.builtInLabels.contains($0) }, ["Passive"])
        try store.delete(seed)
        XCTAssertEqual(Set(store.labels), Set(DescriptionAnalysis.builtInLabels))
    }
    @MainActor func testManufacturerAndPackageHistory() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = try SQLiteRepository(path: path)
        let store = InventoryStore(repository: repository)
        var saved: [Part] = []
        for index in 1...12 {
            var part = Part(); part.number = "P\(index)"; part.manufacturer = "Maker \(index)"; part.package = "Package \(index)"
            try store.save(part, recordFieldUse: true)
            saved.append(part)
        }
        XCTAssertEqual(Array(store.manufacturers.prefix(10)), (3...12).reversed().map { "Maker \($0)" })
        XCTAssertEqual(Array(store.packages.prefix(10)), (3...12).reversed().map { "Package \($0)" })
        var reused = saved[0]; reused.manufacturer = "  maker 1  "; reused.package = " PACKAGE 1 "
        try store.save(reused, recordFieldUse: true)
        XCTAssertEqual(store.manufacturers.first, "Maker 1")
        XCTAssertEqual(store.packages.first, "Package 1")
        XCTAssertEqual(store.manufacturers.count, 12)
        XCTAssertEqual(store.packages.count, 12)
        XCTAssertEqual(store.parts.first(where: { $0.id == reused.id })?.manufacturer, "Maker 1")
        let makers = store.manufacturers; let packages = store.packages
        var stockUpdate = saved[1]; stockUpdate.stock = 10
        try store.save(stockUpdate)
        XCTAssertEqual(store.manufacturers, makers, "Stock changes must not affect field recency")
        XCTAssertEqual(store.packages, packages)
        var invalid = Part(); invalid.manufacturer = "Invalid maker"; invalid.package = "Invalid package"
        XCTAssertThrowsError(try store.save(invalid, recordFieldUse: true))
        XCTAssertFalse(store.manufacturers.contains("Invalid maker"))
        XCTAssertFalse(store.packages.contains("Invalid package"))
        try store.delete(saved[0])
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.manufacturers, makers.filter { $0 != "Maker 1" })
        XCTAssertEqual(reopened.packages, packages.filter { $0 != "Package 1" })
    }
    @MainActor func testAutocompletePrunesOnlyLastAssignment() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = try SQLiteRepository(path: path)
        let store = InventoryStore(repository: repository)
        var first = Part(); first.number = "A"; first.manufacturer = "Murate"; first.package = "0805"; first.labels = ["Inductor"]
        var second = Part(); second.number = "B"; second.manufacturer = "murate"; second.package = "0805"; second.labels = ["inductor"]
        try store.save(first)
        try store.save(second)
        first.manufacturer = "TDK"; first.package = "0603"; first.labels = ["Passive"]
        try store.save(first, recordFieldUse: true)
        XCTAssertEqual(Set(store.manufacturers), ["Murate", "TDK"])
        XCTAssertEqual(Set(store.packages), ["0805", "0603"])
        XCTAssertEqual(Set(store.labels), Set(DescriptionAnalysis.builtInLabels + ["Passive"]))
        second.manufacturer = "TDK"; second.package = "0603"; second.labels = ["Passive"]
        try store.save(second, recordFieldUse: true)
        XCTAssertEqual(store.manufacturers, ["TDK"])
        XCTAssertEqual(store.packages, ["0603"])
        XCTAssertEqual(store.labels.filter { !DescriptionAnalysis.builtInLabels.contains($0) }, ["Passive"])
        XCTAssertFalse(try repository.loadSuggestions(for: .manufacturer).contains("Murate"))
        XCTAssertFalse(try repository.loadSuggestions(for: .package).contains("0805"))
        XCTAssertTrue(try repository.loadLabels().contains("Inductor"), "Built-in labels remain without assignments")
        try store.delete(first)
        XCTAssertEqual(store.manufacturers, ["TDK"])
        XCTAssertEqual(store.packages, ["0603"])
        XCTAssertEqual(store.labels.filter { !DescriptionAnalysis.builtInLabels.contains($0) }, ["Passive"])
        second.manufacturer = ""; second.package = ""; second.labels = []
        try store.save(second)
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertTrue(reopened.manufacturers.isEmpty)
        XCTAssertTrue(reopened.packages.isEmpty)
        XCTAssertEqual(Set(reopened.labels), Set(DescriptionAnalysis.builtInLabels))
    }
    func testStartupRemovesLegacyOrphanSuggestions() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let repository = try SQLiteRepository(path: path)
            var part = Part(); part.number = "A"; part.manufacturer = "TDK"; part.package = "0603"; part.labels = ["Passive"]
            try repository.save(part)
            try repository.registerSuggestion("Murate", for: .manufacturer)
            try repository.registerSuggestion("0805", for: .package)
            try repository.registerLabel("Unused")
        }
        let repository = try SQLiteRepository(path: path)
        XCTAssertEqual(try repository.loadSuggestions(for: .manufacturer), ["TDK"])
        XCTAssertEqual(try repository.loadSuggestions(for: .package), ["0603"])
        XCTAssertEqual(Set(try repository.loadLabels()), Set(DescriptionAnalysis.builtInLabels + ["Passive"]))
    }
    @MainActor func testStorageRecencySharedAssignmentsAndCleanup() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = try SQLiteRepository(path: path)
        let store = InventoryStore(repository: repository)
        var saved: [Part] = []
        for index in 1...12 {
            var part = Part(); part.number = "P\(index)"; part.storage = "Shelf \(index)"
            try store.save(part, recordFieldUse: true)
            saved.append(part)
        }
        XCTAssertEqual(Array(store.storageLocations.prefix(10)), (3...12).reversed().map { "Shelf \($0)" })
        var shared = Part(); shared.number = "Shared"; shared.storage = " shelf 1 "
        try store.save(shared, recordFieldUse: true)
        XCTAssertEqual(store.storageLocations.first, "Shelf 1")
        XCTAssertEqual(store.storageLocations.count, 12)
        XCTAssertEqual(store.parts.first(where: { $0.id == shared.id })?.storage, "Shelf 1")
        var renamed = saved[0]; renamed.storage = "Drawer A"
        try store.save(renamed, recordFieldUse: true)
        XCTAssertTrue(store.storageLocations.contains("Shelf 1"), "Shared locations must remain until their last assignment is removed")
        shared.storage = ""
        try store.save(shared, recordFieldUse: true)
        XCTAssertFalse(store.storageLocations.contains("Shelf 1"))
        let ordering = store.storageLocations
        var stockUpdate = saved[1]; stockUpdate.stock = 5
        try store.save(stockUpdate)
        XCTAssertEqual(store.storageLocations, ordering)
        try store.delete(renamed)
        XCTAssertFalse(store.storageLocations.contains("Drawer A"))
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.storageLocations, ordering.filter { $0 != "Drawer A" })
        XCTAssertFalse(try repository.loadSuggestions(for: .storage).contains("Shelf 1"))
    }
    func testLegacyTypeMigration() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        let legacy = #"{"id":"legacy","number":"L1","manufacturer":"Murata","category":"Inductor","description":"Power inductor","package":"SMD","value":"33 uH","storage":"A1","datasheet":"","barcode":"original-barcode","stock":50}"#
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE parts (id TEXT PRIMARY KEY, barcode TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "INSERT INTO parts VALUES ('legacy','original-barcode','\(legacy)')", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let repository = try SQLiteRepository(path: path)
        let part = try XCTUnwrap(repository.loadParts().first)
        XCTAssertEqual(part.labels, ["Inductor"])
        XCTAssertEqual(part.tolerance, "")
        XCTAssertNil(part.image)
        XCTAssertEqual(part.barcode, "original-barcode")
        XCTAssertEqual(Set(try repository.loadLabels()), Set(DescriptionAnalysis.builtInLabels))
        XCTAssertEqual(try repository.loadSuggestions(for: .manufacturer), ["Murata"])
        XCTAssertEqual(try repository.loadSuggestions(for: .package), ["SMD"])
        XCTAssertEqual(try repository.loadSuggestions(for: .storage), ["A1"])
        try repository.save(part)
        XCTAssertEqual(try repository.loadParts().first, part)
        let payload = String(decoding: try JSONEncoder().encode(part), as: UTF8.self)
        XCTAssertFalse(payload.contains("category"))
    }
    func testBarcodeUniquenessAndCascade() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        var first = Part(); first.number = "A"
        try repository.save(first)
        var second = Part(); second.number = "B"; second.barcode = first.barcode
        XCTAssertThrowsError(try repository.save(second))
        try repository.save(Allocation(partID: first.id, project: "Test", quantity: 1))
        try repository.delete(first)
        XCTAssertTrue(try repository.loadAllocations().isEmpty)
    }
}
