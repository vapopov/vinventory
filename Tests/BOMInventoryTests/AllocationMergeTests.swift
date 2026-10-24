import XCTest
@testable import BOMInventory

final class AllocationMergeTests: XCTestCase {
    @MainActor func testRepeatedAllocationSumsQuantityAppendsReferencesAndPersists() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var part = Part(); part.number = "A"; part.stock = 20
        var other = Part(); other.number = "B"; other.stock = 10
        try store.save(part); try store.save(other)
        try store.allocate(part, project: "Board", quantity: 2, designators: "C1")
        let id = store.allocations[0].id
        try store.allocate(part, project: " board ", quantity: 3, designators: " C2-C4 ")
        XCTAssertEqual(store.allocations.count, 1)
        XCTAssertEqual(store.allocations[0].id, id)
        XCTAssertEqual(store.allocations[0].quantity, 5, "Adding sums quantities independently of reference counts")
        XCTAssertEqual(store.allocations[0].designators, "C1, C2-C4")
        try store.allocate(part, project: "Board", quantity: 1)
        XCTAssertEqual(store.allocations[0].designators, "C1, C2-C4")
        XCTAssertEqual(store.allocations[0].quantity, 6)
        try store.allocate(other, project: "Board", quantity: 1, designators: "R1")
        try store.allocate(part, project: "Other", quantity: 1)
        XCTAssertEqual(store.allocations.count, 3)
        let before = store.allocations
        XCTAssertThrowsError(try store.allocate(part, project: "Board", quantity: 14, designators: "C9"))
        XCTAssertEqual(store.allocations, before)
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.allocations, before)
        XCTAssertEqual(reopened.available(part), 13)
    }
    @MainActor func testLegacyDuplicateRowsMergeOnNextAddition() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        var part = Part(); part.stock = 10
        try repository.save(part)
        let first = Allocation(partID: part.id, project: "Board", quantity: 2)
        try repository.save(first)
        try repository.save(Allocation(partID: part.id, project: "board", quantity: 1, designators: "R1"))
        let store = InventoryStore(repository: repository)
        try store.allocate(part, project: "Board", quantity: 2, designators: "R2, R3")
        XCTAssertEqual(store.allocations.count, 1)
        XCTAssertEqual(store.allocations[0].id, first.id)
        XCTAssertEqual(store.allocations[0].quantity, 5)
        XCTAssertEqual(store.allocations[0].designators, "R1, R2, R3")
    }
}
