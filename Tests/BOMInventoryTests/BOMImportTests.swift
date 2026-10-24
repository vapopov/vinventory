import XCTest
@testable import BOMInventory

final class BOMImportTests: XCTestCase {
    func testLCSCMappingEditingExclusionAndUnknownColumns() throws {
        var document = try BOMImport(text: "LCSC Part Number,Manufacture Part Number,Manufacturer,Package,Description,Quantity,Unit Price($),RoHS\r\nC105871,RC0402,YAGEO,0402,\"Resistor, 4.7kΩ\",100,0.0029,YES\r\nC2,OTHER,Vendor,SMD,Other,2,1.23,YES\r\n", filename: "order.csv")
        XCTAssertEqual(document.rows.count, 2)
        XCTAssertTrue(document.rows.allSatisfy(\.selected))
        document.rows[0].values[5] = "80"
        document.rows[1].selected = false
        let part = try XCTUnwrap(document.selectedParts().first)
        XCTAssertEqual(try document.selectedParts().count, 1)
        XCTAssertEqual(part.lcsc, "C105871")
        XCTAssertEqual(part.number, "RC0402")
        XCTAssertEqual(part.manufacturer, "YAGEO")
        XCTAssertEqual(part.description, "Resistor, 4.7kΩ")
        XCTAssertEqual(part.stock, 80)
        XCTAssertEqual(part.customFields, ["Unit Price($)": "0.0029", "RoHS": "YES"])
        document.rows[0].values[5] = "bad"
        XCTAssertThrowsError(try document.selectedParts())
        document.rows[0].selected = false
        XCTAssertTrue(try document.selectedParts().isEmpty)
    }
    func testCSVQuotesNewlinesAndValidation() throws {
        let rows = try CSVReader.read("\u{FEFF}A,B\r\n\"line one\nline two\",\"quote \"\"here\"\"\"\r\n")
        XCTAssertEqual(rows, [["A", "B"], ["line one\nline two", "quote \"here\""]])
        XCTAssertThrowsError(try CSVReader.read("A\n\"unfinished"))
        XCTAssertThrowsError(try BOMImport(text: "Part Number,part number\nA,B", filename: "x"))
        XCTAssertThrowsError(try BOMImport(text: "Part Number\nA,B", filename: "x"))
    }
    @MainActor func testImportPersistenceSearchAndLegacyDefaults() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        let document = try BOMImport(text: "Part Number,LCSC,Quantity,Storage,Unit Price\nMPN,C1234,5,Drawer,0.42", filename: "x")
        try store.importParts(document.selectedParts())
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.parts.count, 1)
        XCTAssertEqual(reopened.parts[0].customFields, ["Unit Price": "0.42"])
        XCTAssertEqual(reopened.search("C1234").count, 1)
        XCTAssertEqual(reopened.search("Unit Price 0.42").count, 1)
        XCTAssertTrue(reopened.storageSuggestions.contains("Drawer"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reopened.parts[0])) as? [String: Any])
        json.removeValue(forKey: "lcsc"); json.removeValue(forKey: "customFields")
        let legacy = try JSONDecoder().decode(Part.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.lcsc, "")
        XCTAssertTrue(legacy.customFields.isEmpty)
    }
    @MainActor func testInvalidImportAndDatabaseFailureDoNotPartiallySave() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        let store = InventoryStore(repository: repository)
        var valid = Part(); valid.number = "A"; valid.storage = "New"
        var invalid = Part(); invalid.number = "B"; invalid.stock = -1
        XCTAssertThrowsError(try store.importParts([valid, invalid]))
        XCTAssertTrue(try repository.loadParts().isEmpty)
        var duplicateBarcode = Part(); duplicateBarcode.number = "C"; duplicateBarcode.barcode = valid.barcode
        XCTAssertThrowsError(try repository.saveImportedParts([valid, duplicateBarcode]))
        XCTAssertTrue(try repository.loadParts().isEmpty)
        XCTAssertTrue(try repository.loadStorageDescriptions().isEmpty)
    }
    func testCustomFieldNameValidation() throws {
        XCTAssertEqual(try CustomFieldDraft.dictionary([CustomFieldDraft(name: " Price ", value: "0.42")]), ["Price": "0.42"])
        XCTAssertThrowsError(try CustomFieldDraft.dictionary([CustomFieldDraft(name: " ", value: "x")]))
        XCTAssertThrowsError(try CustomFieldDraft.dictionary([CustomFieldDraft(name: "Price"), CustomFieldDraft(name: "price")]))
    }
}
