import XCTest
@testable import BOMInventory

final class ImportMergeTests: XCTestCase {
    @MainActor func testMergeByEitherIdentifierKeepsIdentityDetailsAndAllocations() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var original = Part(); original.number = "MPN-A"; original.lcsc = "C100"; original.stock = 10
        original.description = "Keep me"; original.storage = "Drawer"; original.customFields = ["Price": "Old"]; original.labels = ["Existing"]
        try store.save(original)
        try store.allocate(original, project: "Board", quantity: 2)
        var byNumber = Part(); byNumber.number = " mpn-a "; byNumber.stock = 5; byNumber.labels = ["Resistor", "Manual"]
        var byLCSC = Part(); byLCSC.number = "Other supplier MPN"; byLCSC.lcsc = " c100 "; byLCSC.stock = 3; byLCSC.labels = ["manual"]
        try store.importParts([byNumber, byLCSC])
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.parts.count, 1)
        let saved = try XCTUnwrap(reopened.parts.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.barcode, original.barcode)
        XCTAssertEqual(saved.stock, 18)
        XCTAssertEqual(saved.description, "Keep me")
        XCTAssertEqual(saved.storage, "Drawer")
        XCTAssertEqual(saved.customFields, original.customFields)
        XCTAssertEqual(saved.labels, ["Existing", "Resistor", "Manual"])
        XCTAssertEqual(reopened.available(saved), 16)
        XCTAssertEqual(reopened.allocations.first?.partID, original.id)
    }
    @MainActor func testRepeatedRowsWithinImportCreateOnePartAndFillMissingLCSC() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var a = Part(); a.number = "A"; a.stock = 2
        var b = Part(); b.number = " a "; b.stock = 3; b.lcsc = "C1"
        var c = Part(); c.number = "ALIAS"; c.stock = 4; c.lcsc = "c1"
        try store.importParts([a, b, c])
        XCTAssertEqual(store.parts.count, 1)
        XCTAssertEqual(store.parts[0].stock, 9)
        XCTAssertEqual(store.parts[0].lcsc, "C1")
        XCTAssertEqual(store.parts[0].number, "A")
        XCTAssertEqual(store.parts[0].id, a.id)
        var other = Part(); other.number = "B"; other.stock = 1
        try store.importParts([other])
        XCTAssertEqual(store.parts.count, 2, "Empty LCSC identifiers must never match each other")
    }
    @MainActor func testConflictingIdentifiersAndOverflowLeaveWholeBatchUnchanged() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var a = Part(); a.number = "A"; a.lcsc = "C1"; a.stock = 2
        var b = Part(); b.number = "B"; b.lcsc = "C2"; b.stock = 3
        try store.save(a); try store.save(b)
        var valid = Part(); valid.number = "A"; valid.stock = 5
        var conflict = Part(); conflict.number = "A"; conflict.lcsc = "C2"; conflict.stock = 1
        let before = store.parts
        XCTAssertThrowsError(try store.importParts([valid, conflict]))
        XCTAssertEqual(store.parts, before)
        try store.reload()
        XCTAssertEqual(store.parts, before)
        var overflow = Part(); overflow.number = "A"; overflow.stock = Int.max
        XCTAssertThrowsError(try store.importParts([overflow]))
        XCTAssertEqual(store.parts, before)
    }
    func testMultipleLabelsAndPendingTextAreIncludedOnlyForSelectedRows() throws {
        var document = try BOMImport(text: "Part Number,Labels\nA,Resistor\nB,Capacitor", filename: "x")
        document.rows[1].selected = false
        document.commitPendingLabels([document.rows[0].id: " precision, Resistor, RF ", document.rows[1].id: "Ignored"], suggestions: ["Precision", "Resistor"])
        XCTAssertEqual(try document.selectedParts()[0].labels, ["Resistor", "Precision", "RF"])
        XCTAssertEqual(BOMImport.parseLabels("A, a, B, , B"), ["A", "B"])
        let column = try XCTUnwrap(document.headers.firstIndex(of: "Labels"))
        XCTAssertEqual(document.rows[1].values[column], "Capacitor")
        document.setValue("Precision, RF", row: 0, column: column)
        XCTAssertEqual(try document.selectedParts()[0].labels, ["Precision", "RF"])
    }
}
