import XCTest
import CSQLite
@testable import BOMInventory

final class ProjectTests: XCTestCase {
    @MainActor func testProjectsDesignatorsAndReleasePersist() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        var part = Part(); part.number = "Capacitor"; part.stock = 20
        try store.save(part)
        try store.allocate(part, project: "  Controller  ", quantity: 5, designators: "C16-C20")
        try store.allocate(part, project: "controller", quantity: 3, designators: "R3, R4, R11")
        XCTAssertEqual(store.projects.map(\.name), ["Controller"])
        XCTAssertEqual(store.allocations.map(\.quantity), [8])
        XCTAssertEqual(store.available(part), 12)
        let first = try XCTUnwrap(store.allocations.first)
        XCTAssertEqual(first.designators, "C16-C20, R3, R4, R11")
        try store.saveProjectDescription(name: "CONTROLLER", description: " Main controller PCB ")
        try store.saveDesignators(allocationID: first.id, value: " C21-C25 ")
        XCTAssertEqual(store.allocations.first?.designators, "C21-C25")
        XCTAssertEqual(store.allocations.map(\.quantity), [5], "A five-reference range reserves five units")
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertEqual(reopened.projects.first?.description, "Main controller PCB")
        XCTAssertEqual(reopened.allocations, store.allocations)
        try reopened.release(first)
        XCTAssertTrue(reopened.allocations.isEmpty)
        XCTAssertEqual(reopened.available(part), 20)
        XCTAssertThrowsError(try reopened.saveDesignators(allocationID: first.id, value: "IC2"))
        XCTAssertEqual(reopened.available(part), 20)
        XCTAssertEqual(reopened.projects.map(\.name), ["Controller"], "Projects must remain after all allocations are released")
        XCTAssertEqual(reopened.projects.first?.description, "Main controller PCB")
    }
    @MainActor func testProjectsRemainIsolatedAndInvalidAllocationCreatesNothing() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var part = Part(); part.number = "IC"; part.stock = 4
        try store.save(part)
        try store.allocate(part, project: "Board A", quantity: 1, designators: "IC2")
        try store.allocate(part, project: "Board B", quantity: 2, designators: "IC1, IC3")
        XCTAssertThrowsError(try store.allocate(part, project: "Overdraw", quantity: 2))
        XCTAssertFalse(store.projects.contains { $0.name == "Overdraw" })
        let board = try XCTUnwrap(store.projects.first { $0.name == "Board A" })
        XCTAssertEqual(store.allocations.filter(board.contains).map(\.designators), ["IC2"])
        try store.saveProjectDescription(name: "Board A", description: "Analog board")
        XCTAssertEqual(store.projects.first { $0.name == "Board B" }?.description, "")
    }
    func testDesignatorCounting() throws {
        XCTAssertEqual(try Designators.quantity(in: "R1, R2"), 2)
        XCTAssertEqual(try Designators.quantity(in: "C16-C20"), 5)
        XCTAssertEqual(try Designators.quantity(in: "C1"), 1)
        XCTAssertEqual(try Designators.quantity(in: "C1-C3, C2, R1"), 4)
        XCTAssertNil(try Designators.quantity(in: " "))
        for invalid in ["C3-C1", "C1-R3", "R1,", "nonsense", "C1-999999999999999999999999999"] {
            XCTAssertThrowsError(try Designators.quantity(in: invalid))
        }
    }
    @MainActor func testAllocationEditsRecalculateOnlyChangedDesignatorsAndValidateStock() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var part = Part(); part.number = "Edit"; part.stock = 10
        try store.save(part)
        try store.allocate(part, project: "Board", quantity: 4, designators: "C1")
        try store.allocate(part, project: "Other", quantity: 3)
        let id = store.allocations[0].id
        try store.saveQuantity(allocationID: id, value: "5")
        XCTAssertEqual(store.allocations[0].quantity, 5)
        try store.saveDesignators(allocationID: id, value: "C1")
        XCTAssertEqual(store.allocations[0].quantity, 5)
        try store.saveDesignators(allocationID: id, value: "C16-C20")
        XCTAssertEqual(store.allocations[0].quantity, 5)
        try store.saveDesignators(allocationID: id, value: "R1, R2")
        XCTAssertEqual(store.allocations[0].quantity, 2)
        XCTAssertEqual(store.available(part), 5)
        let before = store.allocations
        XCTAssertThrowsError(try store.saveDesignators(allocationID: id, value: "C1-C8"))
        XCTAssertThrowsError(try store.saveQuantity(allocationID: id, value: "8"))
        XCTAssertThrowsError(try store.saveQuantity(allocationID: id, value: "0"))
        XCTAssertThrowsError(try store.saveQuantity(allocationID: id, value: "1.5"))
        XCTAssertEqual(store.allocations, before)
        try store.saveDesignators(allocationID: id, value: "")
        XCTAssertEqual(store.allocations[0].quantity, 2)
        try store.saveDesignators(allocationID: id, value: "IC2")
        XCTAssertEqual(store.allocations[0].quantity, 1)
    }
    func testProjectCreationRollsBackWhenAllocationCannotBeSaved() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        XCTAssertThrowsError(try repository.save(Allocation(partID: "missing", project: "Failed project", quantity: 1)))
        XCTAssertTrue(try repository.loadProjects().isEmpty)
    }
    @MainActor func testLegacyAllocationsMigrateWithoutLosingReservations() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var part = Part(); part.number = "Legacy"; part.stock = 10
        let allocation = Allocation(partID: part.id, project: " Legacy project ", quantity: 2)
        do {
            let repository = try SQLiteRepository(path: path)
            try repository.save(part)
            try repository.save(allocation)
        }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        let legacy = "{\"id\":\"\(allocation.id)\",\"partID\":\"\(part.id)\",\"project\":\" Legacy project \",\"quantity\":2}"
        XCTAssertEqual(sqlite3_exec(database, "UPDATE allocations SET payload='\(legacy)'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "DROP TABLE projects", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        XCTAssertNil(store.error)
        XCTAssertEqual(store.projects.map(\.name), ["Legacy project"])
        XCTAssertEqual(store.allocations.first?.id, allocation.id)
        XCTAssertEqual(store.allocations.first?.designators, "")
        XCTAssertEqual(store.allocated(part), 2)
        XCTAssertEqual(store.allocations.filter(store.projects[0].contains).count, 1)
        try store.saveDesignators(allocationID: allocation.id, value: "R1, R2")
        XCTAssertEqual(store.allocations.first?.designators, "R1, R2")
        XCTAssertEqual(store.available(part), 8)
    }
}
