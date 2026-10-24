import XCTest
@testable import BOMInventory

final class CatalogTests: XCTestCase {
    @MainActor func testIndependentEntriesPersistAndRenamesCarryAssignments() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(store.locations.map(\.displayName), ["(no storage)"])
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: " Board ", description: " Controller ")
        _ = try store.saveCatalog(kind: .storage, originalName: nil, name: "Drawer", description: "Parts")
        var reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.projects, [Project(name: "Board", description: "Controller")])
        XCTAssertTrue(reopened.locations.contains { $0.name == "Drawer" })
        XCTAssertTrue(reopened.storageSuggestions.contains("Drawer"))
        var part = Part(); part.number = "Test"; part.stock = 10; part.storage = "drawer"
        try reopened.save(part)
        try reopened.allocate(part, project: "board", quantity: 3, designators: "C1-C3")
        let allocationID = reopened.allocations[0].id
        _ = try reopened.saveCatalog(kind: .project, originalName: "Board", name: "Board Rev B", description: "Revised")
        _ = try reopened.saveCatalog(kind: .storage, originalName: "Drawer", name: "Shelf", description: "Moved")
        reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.allocations[0].project, "Board Rev B")
        XCTAssertEqual(reopened.allocations[0].id, allocationID)
        XCTAssertEqual(reopened.allocations[0].designators, "C1-C3")
        XCTAssertEqual(reopened.available(part), 7)
        XCTAssertEqual(reopened.parts[0].storage, "Shelf")
        XCTAssertFalse(reopened.locations.contains { $0.name == "Drawer" })
        try reopened.release(reopened.allocations[0])
        var saved = reopened.parts[0]; saved.storage = ""
        try reopened.save(saved)
        XCTAssertTrue(reopened.projects.contains { $0.name == "Board Rev B" })
        XCTAssertTrue(reopened.locations.contains { $0.name == "Shelf" })
    }
    @MainActor func testDeleteReleasesOnlyTargetProjectAndUnassignsOnlyTargetStorage() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var part = Part(); part.number = "A"; part.stock = 10; part.storage = "A"
        var other = Part(); other.number = "B"; other.storage = "B"
        try store.save(part); try store.save(other)
        try store.allocate(part, project: "Delete", quantity: 3)
        try store.allocate(part, project: "Keep", quantity: 2)
        try store.allocate(part, project: "Delete", quantity: 1)
        try store.deleteCatalog(kind: .project, name: "delete")
        XCTAssertEqual(store.available(part), 8)
        XCTAssertEqual(store.allocations.map(\.project), ["Keep"])
        try store.deleteCatalog(kind: .storage, name: "a")
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.parts.first { $0.id == part.id }?.storage, "")
        XCTAssertEqual(reopened.parts.first { $0.id == other.id }?.storage, "B")
        XCTAssertFalse(reopened.locations.contains { $0.name == "A" })
        XCTAssertFalse(reopened.projects.contains { $0.name == "Delete" })
        XCTAssertEqual(reopened.parts.first { $0.id == part.id }?.stock, 10)
        XCTAssertEqual(reopened.allocations.count, 1)
    }
    @MainActor func testInvalidNamesAndDuplicateRenamesDoNotChangeAssignments() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        for kind in [CatalogKind.project, .storage] {
            _ = try store.saveCatalog(kind: kind, originalName: nil, name: "First", description: "")
            _ = try store.saveCatalog(kind: kind, originalName: nil, name: "Second", description: "")
            XCTAssertThrowsError(try store.saveCatalog(kind: kind, originalName: nil, name: " first ", description: ""))
            XCTAssertThrowsError(try store.saveCatalog(kind: kind, originalName: "First", name: "SECOND", description: ""))
            XCTAssertThrowsError(try store.saveCatalog(kind: kind, originalName: nil, name: " ", description: ""))
            XCTAssertThrowsError(try store.saveCatalog(kind: kind, originalName: nil, name: "(no storage)", description: ""))
            _ = try store.saveCatalog(kind: kind, originalName: "First", name: "FIRST", description: "Case change")
        }
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertEqual(store.locations.count, 3)
    }
}
