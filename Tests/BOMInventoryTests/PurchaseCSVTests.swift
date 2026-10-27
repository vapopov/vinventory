import XCTest
@testable import BOMInventory

final class PurchaseCSVTests: XCTestCase {
    func testFullAndProjectExportsPreserveDetailsAndUseCorrectQuantities() throws {
        var item = PurchaseItem()
        item.part.number = "CAP"
        item.part.stock = 30
        item.part.description = "Capacitor, \"ceramic\"\n50V"
        item.part.customFields = ["Unit Price": "0.12"]
        item.part.labels = ["Capacitor", "SMD"]
        item.assignments = [PurchaseAssignment(project: "Board", quantity: 4, designators: "C1, C2, C3, C4"),
                            PurchaseAssignment(project: "Other", quantity: 2, designators: "C8, C9")]
        var unassigned = PurchaseItem()
        unassigned.part.number = "RES"
        let all = try CSVReader.read(PurchaseCSV.encode([item, unassigned]))
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[1][7], "30")
        XCTAssertEqual(all[1][3], item.part.description)
        XCTAssertEqual(all[1][10], "Capacitor, SMD")
        XCTAssertEqual(all[0].last, "Custom: Unit Price")
        XCTAssertEqual(all[1].last, "0.12")
        XCTAssertEqual(all[2].last, "")
        let board = try CSVReader.read(PurchaseCSV.encode([item, unassigned], project: "board"))
        XCTAssertEqual(board.count, 2)
        XCTAssertEqual(board[1][7], "4")
        XCTAssertEqual(board[1][8], "Board")
        XCTAssertEqual(board[1][9], "C1, C2, C3, C4")
        XCTAssertEqual(try CSVReader.read(PurchaseCSV.encode([item], project: "Missing")).count, 1)
    }
}
