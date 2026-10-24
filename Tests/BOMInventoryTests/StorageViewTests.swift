import XCTest
@testable import BOMInventory

final class StorageViewTests: XCTestCase {
    @MainActor func testStorageDescriptionsPersistAndPartsStayGrouped() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var first = Part(); first.number = "A"; first.storage = "Shelf A"
        var second = Part(); second.number = "B"; second.storage = "shelf a"
        var third = Part(); third.number = "C"; third.storage = "Shelf B"
        var unassigned = Part(); unassigned.number = "D"
        for part in [first, second, third, unassigned] { try store.save(part) }
        XCTAssertEqual(store.locations.map(\.displayName), ["(no storage)", "Shelf A", "Shelf B"])
        try store.saveStorageDescription(name: "shelf a", description: "  Resistors and capacitors  ")
        let shelf = try XCTUnwrap(store.locations.first { $0.name == "Shelf A" })
        XCTAssertEqual(shelf.description, "Resistors and capacitors")
        XCTAssertEqual(Set(store.parts.filter(shelf.contains).map(\.number)), ["A", "B"])
        let none = try XCTUnwrap(store.locations.first { $0.name == nil })
        XCTAssertEqual(store.parts.filter(none.contains).map(\.number), ["D"])
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.locations, store.locations)
        try reopened.saveStorageDescription(name: "Shelf A", description: "Updated description")
        XCTAssertEqual(reopened.locations.first { $0.name == "Shelf A" }?.description, "Updated description")
        XCTAssertEqual(reopened.parts.count, 4)
        third.storage = "Shelf A"
        try reopened.save(third)
        XCTAssertTrue(reopened.locations.contains { $0.name == "Shelf B" })
        try reopened.saveStorageDescription(name: "Shelf B", description: "No assigned parts")
        try reopened.saveStorageDescription(name: "Shelf A", description: "")
        XCTAssertEqual(reopened.locations.first { $0.name == "Shelf A" }?.description, "")
    }
    @MainActor func testExistingStorageAssignmentsAppearWithoutDescriptionMigration() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let repository = try SQLiteRepository(path: path)
            var part = Part(); part.number = "Legacy"; part.storage = "A1"
            try repository.save(part)
        }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(store.locations.map(\.displayName), ["(no storage)", "A1"])
        XCTAssertEqual(store.locations.first { $0.name == "A1" }?.description, "")
    }
}
