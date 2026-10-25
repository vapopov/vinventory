import XCTest
@testable import BOMInventory

final class ProjectBOMTests: XCTestCase {
    @MainActor func testIgnoredImportAndRequestCRUDPreserveAllocatedStock() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let capacitor = part("CAP", value: "10uF", stock: 2)
        try store.save(capacitor)
        var review = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\nC1-C5,0402,5,10uF\nTP1,TestPoint,1,TestPoint", filename: "bom", parts: store.parts)
        review.rows[0].selectedPartID = capacitor.id
        review.rows[1].included = false
        try store.applyProjectBOM(review, projectName: "Board")
        XCTAssertEqual(store.bomEntries(for: "Board").count, 1)
        let entry = try XCTUnwrap(store.bomEntries(for: "Board").first)
        XCTAssertEqual(store.requestedQuantity(entry), 3)
        var item = entry.item; item.quantity = 7; item.value = "Updated"
        try store.saveRequest(project: "Board", existing: entry, item: item)
        let updated = try XCTUnwrap(store.bomEntries(for: "Board").first)
        XCTAssertEqual(store.requestedQuantity(updated), 7)
        try store.deleteRequest(updated)
        XCTAssertEqual(store.requestedQuantity(store.bomEntries(for: "Board")[0]), 0)
        XCTAssertEqual(store.allocations.first?.quantity, 2)
        try store.saveRequest(project: "Board", existing: nil, item: item)
        let added = try XCTUnwrap(store.bomEntries(for: "Board").first { $0.id != entry.id })
        try store.deleteRequest(added)
        XCTAssertEqual(store.bomEntries(for: "Board").count, 1)
    }
    @MainActor func testSyncRequestsUsesNewStockWithoutDuplicatesAndSkipsAmbiguousMatches() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        var cap = part("CAP", value: "10uF", stock: 2)
        try store.save(cap)
        var review = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\nC1-C5,0402,5,10uF\nU1,QFN,1,NEW", filename: "bom", parts: store.parts)
        review.rows[0].selectedPartID = cap.id
        try store.applyProjectBOM(review, projectName: "Board")
        func checkedMatches() -> [String: String] {
            Dictionary(uniqueKeysWithValues: store.bomEntries(for: "Board").compactMap { entry in
                let candidates = store.requestCandidates(entry)
                return candidates.count == 1 ? (entry.id, candidates[0].id) : nil
            })
        }
        XCTAssertEqual(try store.syncRequests(project: "Board", matches: [:]), 0, "Review without checked rows must not allocate")
        let allocationID = try XCTUnwrap(store.allocations.first?.id)
        cap.stock = 4; try store.save(cap)
        try store.save(part("NEW", package: "QFN", stock: 1))
        XCTAssertEqual(try store.syncRequests(project: "Board", matches: checkedMatches()), 3)
        XCTAssertEqual(store.allocations.first { $0.id == allocationID }?.quantity, 4)
        XCTAssertEqual(store.bomEntries(for: "Board").map { store.requestedQuantity($0) }.reduce(0, +), 1)
        XCTAssertEqual(try store.syncRequests(project: "Board", matches: checkedMatches()), 0)
        cap.stock = 6; try store.save(cap)
        XCTAssertEqual(try store.syncRequests(project: "Board", matches: checkedMatches()), 1)
        XCTAssertEqual(store.allocations.count, 2)
        try store.save(part("R-A", value: "1kΩ")); try store.save(part("R-B", value: "1kΩ"))
        try store.saveRequest(project: "Board", existing: nil, item: ProjectBOMItem(designators: "R1", package: "0402", quantity: 1, value: "1K", lcsc: ""))
        XCTAssertEqual(try store.syncRequests(project: "Board", matches: checkedMatches()), 0)
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.allocations.count, 2)
        XCTAssertEqual(reopened.bomEntries(for: "Board").map { reopened.requestedQuantity($0) }.reduce(0, +), 1)
    }
    private func part(_ number: String, value: String = "", package: String = "0402", stock: Int = 10) -> Part {
        var part = Part(); part.number = number; part.value = value; part.package = package; part.stock = stock; return part
    }
    func testPassiveMatchingNormalizesNotationUnitsAndPackage() throws {
        let values = [("24K", "24kΩ", "Resistor"), ("1K5Ohm", "1.5kΩ", "Resistor"), ("4K7", "4.7kΩ", "Resistor"), ("650R 1%", "650Ω", "Resistor"), ("10uF", "10000nF", "Capacitor"), ("2.2uH", "2200nH", "Inductor"), ("40MHz", "40000000Hz", "Crystal")]
        for (source, inventory, kind) in values {
            let prefix = ["Resistor": "R", "Capacitor": "C", "Inductor": "L", "Crystal": "Y"][kind]!
            let candidate = part("Candidate", value: inventory)
            let wrong = part("Wrong package", value: inventory, package: "0603")
            let item = ProjectBOMItem(designators: prefix + "1", package: "Library:Some_0402_Pad", quantity: 1, value: source, lcsc: "")
            XCTAssertEqual(ProjectBOMMatcher.candidates(for: item, parts: [candidate, wrong]).map(\.id), [candidate.id], source)
        }
        let one = part("One", value: "10uF"), two = part("Two", value: "10uF")
        let item = ProjectBOMItem(designators: "C1", package: "0402", quantity: 1, value: "10uF", lcsc: "")
        XCTAssertEqual(Set(ProjectBOMMatcher.candidates(for: item, parts: [one, two]).map(\.id)), [one.id, two.id])
        XCTAssertEqual(ProjectBOMMatcher.package("Crystal_SMD_3225-4Pin_3.2x2.5mm"), ProjectBOMMatcher.package("SMD3225-4P"))
    }
    func testParseKiCadRowsAndExactSupplierAndPrefixCandidates() throws {
        var candidate = part("TPS22810DRVR"); candidate.lcsc = "C100"
        let review = try ProjectBOMImport(text: "\u{FEFF}Designator,Footprint,Quantity,Value,LCSC Part #\r\nU1,WSON,1,TPS22810DRV,\r\nU2,WSON,1,Other,C100\r\n", filename: "bom", parts: [candidate])
        XCTAssertEqual(review.rows.count, 2)
        XCTAssertEqual(review.rows[0].candidates, [candidate.id])
        XCTAssertEqual(review.rows[1].candidates, [candidate.id])
        XCTAssertTrue(review.rows.allSatisfy { $0.selectedPartID == nil }, "New matches require confirmation")
        XCTAssertThrowsError(try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\nC1,0402,1,10uF\nC1,0402,1,10uF", filename: "x", parts: []))
    }
    @MainActor func testReviewShortagesRequestedExportAndIdempotentReimport() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let capacitor = part("CAP", value: "10uF", stock: 3)
        let resistor = part("RES", value: "1.5kΩ", stock: 10)
        try store.save(capacitor); try store.save(resistor)
        let csv = "Designator,Footprint,Quantity,Value,LCSC Part #\n\"C1, C2, C3, C4, C5\",0402,5,10uF,\nR1,0402,1,1K5Ohm,\nU1,QFN,1,MISSING,"
        var review = try ProjectBOMImport(text: csv, filename: "bom", parts: store.parts)
        review.rows[0].selectedPartID = capacitor.id
        try store.applyProjectBOM(review, projectName: "Board")
        XCTAssertEqual(store.allocations.count, 1)
        XCTAssertEqual(store.allocations[0].quantity, 3)
        XCTAssertEqual(store.available(capacitor), 0)
        XCTAssertEqual(store.bomEntries(for: "Board").map { store.requestedQuantity($0) }, [2, 1, 1])
        let exported = try CSVReader.read(store.requestedCSV(project: "Board"))
        XCTAssertEqual(exported.count, 4)
        XCTAssertEqual(exported[1][2], "2")
        XCTAssertEqual(exported[2][3], "1K5Ohm")
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        var again = try ProjectBOMImport(text: csv, filename: "bom", parts: reopened.parts, previous: reopened.bomEntries(for: "Board"))
        XCTAssertEqual(again.rows[0].selectedPartID, capacitor.id)
        again.rows[1].selectedPartID = resistor.id
        let allocationID = reopened.allocations[0].id
        try reopened.applyProjectBOM(again, projectName: "Board")
        XCTAssertEqual(reopened.allocations.count, 2)
        XCTAssertEqual(reopened.allocations.first { $0.partID == capacitor.id }?.quantity, 3)
        XCTAssertEqual(reopened.allocations.first { $0.partID == capacitor.id }?.id, allocationID)
        XCTAssertEqual(reopened.bomEntries(for: "Board").count, 3)
        XCTAssertEqual(reopened.requestedQuantity(reopened.bomEntries(for: "Board")[1]), 0)
        // An unchecked previously confirmed row becomes requested, releasing its old reservation.
        again.rows[0].selectedPartID = nil
        try reopened.applyProjectBOM(again, projectName: "Board")
        XCTAssertEqual(reopened.available(capacitor), 3)
        XCTAssertEqual(reopened.requestedQuantity(reopened.bomEntries(for: "Board")[0]), 5)
        _ = try reopened.saveCatalog(kind: .project, originalName: "Board", name: "Board B", description: "")
        XCTAssertEqual(reopened.bomEntries(for: "Board B").count, 3)
        try reopened.deleteCatalog(kind: .project, name: "Board B")
        XCTAssertTrue(reopened.projectBOMEntries.isEmpty)
        XCTAssertTrue(reopened.allocations.isEmpty)
    }
    @MainActor func testReimportOverridesExistingDesignatorSetAndPreservesOtherAllocations() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        let candidate = part("CAP", value: "10uF", stock: 20); try store.save(candidate)
        try store.allocate(candidate, project: "Board", quantity: 3, designators: "C1-C3")
        try store.allocate(candidate, project: "Other", quantity: 2, designators: "C10, C11")
        var review = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\n\"C3, C1, C2\",0402,3,10uF", filename: "bom", parts: store.parts)
        review.rows[0].selectedPartID = candidate.id
        try store.applyProjectBOM(review, projectName: "Board")
        XCTAssertEqual(store.allocations.count, 2)
        XCTAssertEqual(store.allocated(candidate), 5)
        try store.applyProjectBOM(review, projectName: "Board")
        XCTAssertEqual(store.allocated(candidate), 5)
    }
    @MainActor func testRegroupedReferencesReplaceOnlyImportedReferences() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        let candidate = part("CAP", value: "10uF", stock: 20); try store.save(candidate)
        try store.allocate(candidate, project: "Board", quantity: 3, designators: "C1-C3")
        var review = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\nC1,0402,1,10uF", filename: "bom", parts: store.parts)
        review.rows[0].selectedPartID = candidate.id
        try store.applyProjectBOM(review, projectName: "Board")
        XCTAssertEqual(store.allocated(candidate), 3)
        XCTAssertEqual(store.allocations.count, 2)
        XCTAssertTrue(store.allocations.contains { $0.designators == "C2, C3" && $0.quantity == 2 })
        // Merging through PARTS must keep BOM tracking connected to the surviving allocation.
        try store.allocate(candidate, project: "Board", quantity: 1, designators: "C4")
        XCTAssertEqual(store.allocations.count, 1)
        XCTAssertEqual(store.requestedQuantity(store.bomEntries(for: "Board")[0]), 0)
        try store.applyProjectBOM(review, projectName: "Board")
        XCTAssertEqual(store.allocated(candidate), 4)
        XCTAssertEqual(store.requestedQuantity(store.bomEntries(for: "Board")[0]), 0)
    }
    @MainActor func testRequestedGroupsRegroupWithoutDuplicatingReferences() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let first = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\n\"C1, C2\",0402,2,10uF", filename: "bom", parts: [])
        try store.applyProjectBOM(first, projectName: "Board")
        let second = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value\nC1,0402,1,22uF", filename: "bom", parts: [])
        try store.applyProjectBOM(second, projectName: "Board")
        XCTAssertEqual(store.bomEntries(for: "Board").count, 2)
        XCTAssertEqual(store.bomEntries(for: "Board").reduce(0) { $0 + store.requestedQuantity($1) }, 2)
        XCTAssertTrue(store.bomEntries(for: "Board").contains { $0.item.designators == "C2" && $0.item.value == "10uF" })
        XCTAssertTrue(store.bomEntries(for: "Board").contains { $0.item.designators == "C1" && $0.item.value == "22uF" })
    }
    func testProjectImportTransactionRollbackPreservesReservations() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        let candidate = part("CAP"); try repository.save(candidate)
        let original = Allocation(partID: candidate.id, project: "Board", quantity: 1, designators: "C1")
        try repository.save(original)
        let entry = ProjectBOMEntry(project: "Board", item: ProjectBOMItem(designators: "C1", package: "0402", quantity: 1, value: "10uF", lcsc: ""))
        XCTAssertThrowsError(try repository.saveProjectBOM(entries: [entry], allocations: [Allocation(partID: "missing", project: "Board", quantity: 1)], removing: [original.id], removingEntries: []))
        XCTAssertEqual(try repository.loadAllocations(), [original])
        XCTAssertTrue(try repository.loadProjectBOMEntries().isEmpty)
    }

}
