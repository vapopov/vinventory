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
    @MainActor func testBulkAssignmentsValidateBeforeSavingAndCanChangeProject() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        for name in ["A", "B"] { _ = try store.saveCatalog(kind: .project, originalName: nil, name: name, description: "") }
        var one = PurchaseItem(); one.part.number = "ONE"; one.part.stock = 5
        var two = PurchaseItem(); two.part.number = "TWO"; two.part.stock = 2
        try store.savePurchase(one); try store.savePurchase(two)
        let first = Allocation(partID: one.id, project: "A", quantity: 2, designators: "R1, R2")
        let invalid = Allocation(partID: two.id, project: "A", quantity: 3)
        XCTAssertThrowsError(try store.assignPurchaseBulk(project: "A", drafts: [first, invalid]))
        XCTAssertTrue(store.purchases.allSatisfy { $0.assignments.isEmpty })
        let second = Allocation(partID: two.id, project: "A", quantity: 1, designators: "U1")
        try store.assignPurchaseBulk(project: "A", drafts: [first, second])
        XCTAssertEqual(store.purchases.flatMap(\.assignments).count, 2)
        XCTAssertEqual(store.purchaseSearch("R2").map(\.id), [one.id])
        try store.editPurchaseAssignment(itemID: one.id, originalProject: "A", project: "B", quantity: 2, designators: "R1, R2")
        XCTAssertEqual(store.purchases.first { $0.id == one.id }?.assignments.map(\.project), ["B"])
        let reopened = try makeStore(path)
        XCTAssertEqual(reopened.purchases.flatMap(\.assignments).count, 2)
    }
    @MainActor func testAPICreationAnalyzesDescriptionAndPreservesExplicitFields() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        let router = InventoryAPIRouter(store: store)
        let data = try JSONSerialization.data(withJSONObject: ["part": ["number": "RES", "description": "4.7kΩ ±1% 62.5mW 0402 Thick Film Resistor", "labels": ["Custom"]], "quantity": 10])
        XCTAssertEqual(router.handle(method: "POST", target: "/v1/purchases", body: data).status, 201)
        let part = try XCTUnwrap(store.purchases.first?.part)
        XCTAssertEqual(part.value, "4.7kΩ")
        XCTAssertEqual(part.tolerance, "±1%")
        XCTAssertEqual(Set(part.labels), ["Custom", "Resistor"])
        let explicit = try JSONSerialization.data(withJSONObject: ["part": ["number": "CAP", "description": "15pF ±1% Ceramic Capacitor", "value": "22pF", "tolerance": "5%"]])
        XCTAssertEqual(router.handle(method: "POST", target: "/v1/purchases", body: explicit).status, 201)
        let capacitor = try XCTUnwrap(store.purchases.first { $0.part.number == "CAP" }?.part)
        XCTAssertEqual(capacitor.value, "22pF")
        XCTAssertEqual(capacitor.tolerance, "5%")
        XCTAssertTrue(capacitor.labels.contains("Capacitor"))
    }
    @MainActor func testRepeatedAPIPurchasesMergeByNumberOrLCSCAndSumProjectAssignments() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let router = InventoryAPIRouter(store: store)
        func post(_ number: String, _ lcsc: String, _ count: Int, _ assigned: Int, _ refs: String) throws -> APIResponse {
            let body: [String: Any] = ["part": ["number": number, "lcsc": lcsc], "quantity": count, "assignments": [["project": "board", "quantity": assigned, "designators": refs]]]
            return router.handle(method: "POST", target: "/v1/purchases", body: try JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(try post("CAP", "C123", 5, 2, "C1, C2").status, 201)
        let original = try XCTUnwrap(store.purchases.first)
        XCTAssertEqual(try post(" cap ", "", 3, 1, "C3").status, 200)
        let response = try post("Different supplier number", " c123 ", 2, 1, "C4")
        XCTAssertEqual(response.status, 200)
        let returned = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        XCTAssertEqual(returned["id"] as? String, original.id)
        XCTAssertEqual(store.purchases.count, 1)
        XCTAssertEqual(store.purchases[0].part.stock, 10)
        XCTAssertEqual(store.purchases[0].part.barcode, original.part.barcode)
        XCTAssertEqual(store.purchases[0].assignments[0].id, original.assignments[0].id)
        XCTAssertEqual(store.purchases[0].assignments[0].quantity, 4)
        XCTAssertEqual(store.purchases[0].assignments[0].designators, "C1, C2, C3, C4")
        XCTAssertTrue(store.parts.isEmpty)
        XCTAssertEqual(try post("CAP", "C123", 1, 2, "C5").status, 400)
        XCTAssertEqual(store.purchases[0].part.stock, 10)
        let reopened = try makeStore(path)
        XCTAssertEqual(reopened.purchases[0].part.stock, 10)
        XCTAssertEqual(reopened.purchases[0].assignments[0].quantity, 4)
    }
    @MainActor func testProjectPurchasePOSTAddsWhilePATCHReplaces() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try makeStore(path)
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        var item = PurchaseItem(); item.part.number = "ABC"; item.part.stock = 2
        try store.savePurchase(item)
        let router = InventoryAPIRouter(store: store)
        func call(_ method: String, _ count: Int, _ refs: String) throws -> APIResponse {
            let body: [String: Any] = ["purchaseID": item.id, "quantity": count, "designators": refs]
            let target = "/v1/projects/Board/purchase" + (method == "PATCH" ? "/" + item.id : "")
            return router.handle(method: method, target: target, body: try JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(try call("POST", 2, "R1, R2").status, 201)
        XCTAssertEqual(try call("POST", 3, "R3-R5").status, 200)
        XCTAssertEqual(store.purchases[0].assignments[0].quantity, 5)
        XCTAssertEqual(store.purchases[0].assignments[0].designators, "R1, R2, R3-R5")
        XCTAssertEqual(store.purchases[0].part.stock, 5)
        XCTAssertEqual(try call("PATCH", 1, "R1").status, 200)
        XCTAssertEqual(store.purchases[0].assignments[0].quantity, 1)
        XCTAssertEqual(store.purchases[0].part.stock, 5)
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
