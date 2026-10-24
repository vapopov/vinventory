import XCTest
@testable import BOMInventory

final class BulkAllocationTests: XCTestCase {
    @MainActor func testBulkSavesOnlyFilledRowsAndPersists() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        var a = Part(); a.number = "A"; a.stock = 10
        var b = Part(); b.number = "B"; b.stock = 10
        var c = Part(); c.number = "C"; c.stock = 10
        for part in [a, b, c] { try store.save(part) }
        let drafts = [Allocation(partID: a.id, project: "ignored", quantity: 2), Allocation(partID: b.id, project: "ignored", quantity: 3, designators: "C1-C3"), Allocation(partID: c.id, project: "ignored", quantity: 0)]
        try store.allocateBulk(projectName: "board", drafts: drafts)
        XCTAssertEqual(store.allocations.count, 2)
        XCTAssertEqual(Set(store.allocations.map(\.project)), ["Board"])
        XCTAssertEqual(store.available(a), 8)
        XCTAssertEqual(store.available(b), 7)
        XCTAssertEqual(store.available(c), 10)
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.allocations, store.allocations)
    }
    @MainActor func testInvalidBulkCreatesNothingAndPreservesExistingAllocations() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var a = Part(); a.number = "A"; a.stock = 5
        var b = Part(); b.number = "B"; b.stock = 1
        for part in [a, b] { try store.save(part) }
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let valid = Allocation(partID: a.id, project: "Board", quantity: 2)
        let invalid = Allocation(partID: b.id, project: "Board", quantity: 2)
        XCTAssertThrowsError(try store.allocateBulk(projectName: "Board", drafts: [valid, invalid]))
        XCTAssertTrue(store.allocations.isEmpty)
        try store.allocate(a, project: "Board", quantity: 1)
        let before = store.allocations
        XCTAssertThrowsError(try store.allocateBulk(projectName: "Board", drafts: [Allocation(partID: b.id, project: "Board", quantity: 1), valid]))
        XCTAssertEqual(store.allocations, before)
        XCTAssertThrowsError(try store.allocateBulk(projectName: "Missing", drafts: [valid]))
    }
    func testBatchDatabaseFailureRollsBackEarlierRowsAndProjectCreation() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        let part = Part(); try repository.save(part)
        XCTAssertThrowsError(try repository.saveAllocations([Allocation(partID: part.id, project: "New", quantity: 1), Allocation(partID: "missing", project: "New", quantity: 1)]))
        XCTAssertTrue(try repository.loadAllocations().isEmpty)
        XCTAssertTrue(try repository.loadProjects().isEmpty)
    }
}
