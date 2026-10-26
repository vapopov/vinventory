import XCTest
@testable import BOMInventory

final class PurchaseTests: XCTestCase {
    @MainActor private func makeStore(_ path: String) throws -> InventoryStore { InventoryStore(repository: try SQLiteRepository(path: path)) }
    @MainActor func testCartReceiptMergesStockAndReservesProjectWithoutDoubleReceiving() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        var inventory = Part(); inventory.number = "CAP"; inventory.stock = 10; inventory.lcsc = "C123"
        try store.save(inventory)
        var purchase = PurchaseItem(); purchase.part.number = "CAP supplier variant"; purchase.part.lcsc = "C123"; purchase.part.stock = 5
        purchase.assignments = [PurchaseAssignment(project: "Board", quantity: 3, designators: "C1-C3")]
        try store.savePurchase(purchase)
        XCTAssertEqual(store.parts.first?.stock, 10)
        XCTAssertTrue(store.allocations.isEmpty)
        let reopened = try makeStore(path)
        XCTAssertEqual(reopened.purchases.count, 1)
        XCTAssertEqual(try reopened.receivePurchases(ids: [purchase.id]), [inventory.id])
        XCTAssertTrue(reopened.purchases.isEmpty)
        XCTAssertEqual(reopened.parts.count, 1)
        XCTAssertEqual(reopened.parts.first?.stock, 15)
        XCTAssertEqual(reopened.allocations.first?.quantity, 3)
        XCTAssertEqual(reopened.available(reopened.parts[0]), 12)
        XCTAssertThrowsError(try reopened.receivePurchases(ids: [purchase.id]))
        XCTAssertEqual(reopened.parts.first?.stock, 15)
    }
    @MainActor func testAssignmentsValidationRenameDeletionAndNewInventoryReceipt() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        var item = PurchaseItem(); item.part.number = "NEW"; item.part.stock = 10
        try store.savePurchase(item)
        try store.savePurchaseAssignment(itemID: item.id, project: "Board", quantity: 1, designators: "R1-R3", inferQuantity: true)
        XCTAssertEqual(store.purchases[0].assignments[0].quantity, 3)
        XCTAssertThrowsError(try store.savePurchaseAssignment(itemID: item.id, project: "Board", quantity: 11, designators: ""))
        _ = try store.saveCatalog(kind: .project, originalName: "Board", name: "Renamed", description: "")
        XCTAssertEqual(store.purchases[0].assignments[0].project, "Renamed")
        try store.deleteCatalog(kind: .project, name: "Renamed")
        XCTAssertTrue(store.purchases[0].assignments.isEmpty)
        XCTAssertThrowsError(try store.receivePurchases(ids: [item.id, "missing"]))
        XCTAssertTrue(store.parts.isEmpty)
        try store.receivePurchases(ids: [item.id])
        XCTAssertEqual(store.parts[0].id, item.id)
        XCTAssertEqual(store.parts[0].stock, 10)
    }
    @MainActor func testFailedReceiptRollsBackAndMatchingRequestedGroupIsFulfilled() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repository = try SQLiteRepository(path: path)
        let store = InventoryStore(repository: repository)
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        var item = PurchaseItem(); item.part.number = "CAP"; item.part.stock = 5
        item.assignments = [PurchaseAssignment(project: "Board", quantity: 3, designators: "C1-C3")]
        try store.savePurchase(item)
        XCTAssertThrowsError(try repository.receivePurchases(parts: [item.part], allocations: [Allocation(partID: "invalid", project: "Board", quantity: 1)], entries: [], removing: [item.id]))
        XCTAssertTrue(try repository.loadParts().isEmpty)
        XCTAssertEqual(try repository.loadPurchases().count, 1)
        try store.saveRequest(project: "Board", existing: nil, item: ProjectBOMItem(designators: "C1-C3", package: "", quantity: 3, value: "CAP", lcsc: ""))
        try store.receivePurchases(ids: [item.id])
        XCTAssertEqual(store.requestedQuantity(store.bomEntries(for: "Board")[0]), 0)
        XCTAssertEqual(store.allocations[0].quantity, 3)
    }
    @MainActor func testAPIManagesCartAndProjectPurchases() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let router = InventoryAPIRouter(store: store)
        func call(_ method: String, _ target: String, _ body: [String: Any] = [:]) throws -> APIResponse {
            router.handle(method: method, target: target, body: try JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(try call("POST", "/v1/purchases", ["part": ["number": "ABC"], "quantity": 6]).status, 201)
        let item = try XCTUnwrap(store.purchases.first)
        XCTAssertEqual(try call("PATCH", "/v1/purchases/" + item.id, ["part": ["description": "Demo"]]).status, 200)
        XCTAssertEqual(try call("POST", "/v1/projects/Board/purchase", ["purchaseID": item.id, "quantity": 2]).status, 201)
        XCTAssertEqual(try call("PATCH", "/v1/projects/Board/purchase/" + item.id, ["designators": "U1-U3"]).status, 200)
        XCTAssertEqual(store.purchases[0].assignments[0].quantity, 3)
        XCTAssertEqual(try call("GET", "/v1/projects/Board/purchase").status, 200)
        XCTAssertEqual(try call("POST", "/v1/purchases/receive", ["ids": [item.id]]).status, 200)
        XCTAssertEqual(store.parts[0].stock, 6)
        XCTAssertEqual(store.allocations[0].quantity, 3)
        XCTAssertEqual(try call("POST", "/v1/purchases/receive", ["ids": [item.id]]).status, 400)
        XCTAssertEqual(try call("POST", "/v1/purchases", ["part": ["number": "Delete me"], "quantity": 1]).status, 201)
        let another = try XCTUnwrap(store.purchases.first)
        XCTAssertEqual(try call("DELETE", "/v1/purchases/" + another.id).status, 200)
        XCTAssertEqual(store.parts.count, 1)
    }
}
