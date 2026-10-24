import XCTest
import SwiftUI
import AppKit
@testable import BOMInventory

final class AllocationTableTests: XCTestCase {
    @MainActor func testWrappedRowsGrowAndRespondToColumnWidth() {
        var part = Part(); part.number = "Test"
        let allocation = Allocation(partID: part.id, project: "Test", quantity: 6, designators: "C3, C4,C99,C103,C1,C300,C4")
        let view = PartsTable(parts: [part], selection: .constant(nil), allocations: [allocation])
        let coordinator = view.makeCoordinator()
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("designators"))
        column.width = 180
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        table.usesAutomaticRowHeights = false
        table.rowSizeStyle = .custom
        table.reloadData()
        let narrow = coordinator.tableView(table, heightOfRow: 0)
        XCTAssertGreaterThan(narrow, 30)
        XCTAssertEqual(table.rect(ofRow: 0).height, narrow)
        column.width = 400
        XCTAssertEqual(coordinator.tableView(table, heightOfRow: 0), 30)
    }
}
