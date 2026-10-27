import AppKit
import SwiftUI

struct ProjectRequestRow: Equatable {
    var id: String
    var values: [String]
}

struct ProjectRequestsTable: NSViewRepresentable {
    var rows: [ProjectRequestRow]
    @Binding var selection: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = NSColor(Theme.row)
        let table = NSTableView()
        table.headerView = NSTableHeaderView()
        table.backgroundColor = NSColor(Theme.row)
        table.intercellSpacing = NSSize(width: 1, height: 1)
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.style = .plain
        table.rowSizeStyle = .custom
        table.rowHeight = 30
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        let columns: [(String, CGFloat)] = [("#", 40), ("Designators", 180), ("Requested", 90), ("Value / Part Number", 220), ("Package", 170), ("Supplier / SPN", 160)]
        for (index, definition) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = definition.0
            column.width = definition.1
            column.minWidth = 40
            column.headerCell.font = .systemFont(ofSize: 12, weight: .medium)
            table.addTableColumn(column)
        }
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        guard coordinator.rows != rows || !coordinator.initialized else { return }
        coordinator.parent = self
        coordinator.rows = rows
        coordinator.initialized = true
        table.reloadData()
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ProjectRequestsTable
        init(parent: ProjectRequestsTable) { self.parent = parent }
        var rows: [ProjectRequestRow] = []
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = notification.object as? NSTableView else { return }
            parent.selection = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        }
        var initialized = false
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InventoryRowView() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn, let index = Int(column.identifier.rawValue) else { return nil }
            let cell = NSView()
            let label = NSTextField(wrappingLabelWithString: rows[row].values[index])
            label.font = .systemFont(ofSize: 13)
            label.textColor = NSColor.white.withAlphaComponent(0.88)
            label.maximumNumberOfLines = index == 1 ? 0 : 1
            label.lineBreakMode = index == 1 ? .byWordWrapping : .byTruncatingTail
            label.alignment = index == 0 || index == 2 ? .right : .left
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -9),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            let width = max(1, tableView.tableColumns[1].width - 18)
            let bounds = (rows[row].values[1] as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)])
            return max(30, ceil(bounds.height) + 12)
        }
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let table = notification.object as? NSTableView else { return }
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        }
    }
}
