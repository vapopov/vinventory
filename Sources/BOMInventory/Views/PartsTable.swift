import SwiftUI
import AppKit
// AppKit provides exact row selection colors and desktop column resizing.
struct PartsTable: NSViewRepresentable {
    var parts: [Part]
    @Binding var selection: String?
    var allocations: [Allocation]? = nil
    var rowNumberOffset = 0
    var draftMode = false
    var saveDesignators: ((Allocation, String) throws -> Void)? = nil
    var saveQuantity: ((Allocation, String) throws -> Void)? = nil
    var releaseAllocation: ((Allocation) -> Void)? = nil
    var preview: ((Part, PartPreviewDismissAction) -> AnyView)? = nil
    private var rows: [PartTableRow] {
        guard let allocations else { return parts.map { PartTableRow(id: $0.id, part: $0) } }
        let lookup = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0) })
        return allocations.enumerated().compactMap { index, allocation in
            guard let part = lookup[allocation.partID] else { return nil }
            return PartTableRow(id: allocation.id, part: part, allocation: allocation, number: rowNumberOffset + index + 1)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Theme.row)
        let table = NSTableView()
        table.headerView = NSTableHeaderView()
        table.rowHeight = 30
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = NSSize(width: 1, height: 1)
        table.backgroundColor = NSColor(Theme.row)
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.style = .plain
        table.rowSizeStyle = .custom
        table.target = context.coordinator
        table.action = #selector(Coordinator.rowClicked(_:))
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observeScrolling(scroll.contentView)
        var columns: [(String, String, CGFloat)] = [("number", "Part Number", 160), ("manufacturer", "Manufacturer", 150), ("lcsc", "LCSC", 100), ("description", "Description", 220), ("package", "Package", 90), ("value", "Value", 80), ("tolerance", "Tolerance", 85), ("stock", "Stock Balance", 110), ("storage", "Storage", 120)]
        if allocations != nil { columns.insert(contentsOf: [("rowNumber", "#", 40), ("designators", "Designators", 180), ("quantity", "Qty", 65)] + (draftMode ? [] : [("release", "", 80)]), at: 0) }
        for (key, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title; column.width = width; column.minWidth = 55
            column.headerCell.font = .systemFont(ofSize: 12, weight: .medium)
            table.addTableColumn(column)
        }
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let updatedRows = rows
        let changed = coordinator.rows != updatedRows
        let rowsChanged = coordinator.rows.map(\.id) != updatedRows.map(\.id)
        if rowsChanged { coordinator.closePreview() }
        coordinator.parent = self
        coordinator.rows = updatedRows
        guard let table = coordinator.table else { return }
        coordinator.updating = true
        if changed || !coordinator.heightLayoutReady || table.numberOfRows != updatedRows.count {
            coordinator.heightLayoutReady = true
            table.reloadData()
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<updatedRows.count))
        }
        if let index = updatedRows.firstIndex(where: { $0.id == selection }) {
            if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        } else { table.deselectAll(nil) }
        coordinator.updating = false
        if let id = coordinator.previewPartID, !updatedRows.contains(where: { $0.id == id }) { coordinator.closePreview() }
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSPopoverDelegate {
        var parent: PartsTable
        weak var table: NSTableView?
        var updating = false
        var heightLayoutReady = false
        var rows: [PartTableRow]
        var previewPartID: String?
        private var popover: NSPopover?
        private var scrollObserver: NSObjectProtocol?
        init(_ parent: PartsTable) { self.parent = parent; rows = parent.rows }
        func observeScrolling(_ clip: NSClipView) {
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.closePreview() }
        }
        @objc func rowClicked(_ sender: NSTableView) {
            guard rows.indices.contains(sender.clickedRow) else { return }
            if sender.clickedColumn >= 0, ["designators", "quantity", "release"].contains(sender.tableColumns[sender.clickedColumn].identifier.rawValue) { return }
            showPreview(row: sender.clickedRow)
        }
        private func previewCell(id: String) {
            guard let table, let row = rows.firstIndex(where: { $0.id == id }) else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            showPreview(row: row)
        }
        private func showPreview(row: Int) {
            guard let sender = table, let builder = parent.preview, rows.indices.contains(row) else { return }
            let item = rows[row]
            let part = item.part
            closePreview()
            let popup = NSPopover()
            popup.behavior = .semitransient
            popup.animates = false
            popup.appearance = NSAppearance(named: .darkAqua)
            popup.delegate = self
            let dismiss = PartPreviewDismissAction { [weak popup] in popup?.close() }
            popup.contentViewController = NSHostingController(rootView: builder(part, dismiss))
            popup.contentSize = NSSize(width: 560, height: 420)
            popover = popup
            previewPartID = item.id
            let anchorColumn = sender.tableColumns.firstIndex { $0.identifier.rawValue == "number" } ?? 0
            let cell = sender.frameOfCell(atColumn: anchorColumn, row: row).intersection(sender.visibleRect)
            let anchor = cell.isNull || cell.isEmpty ? sender.rect(ofRow: row).intersection(sender.visibleRect) : cell
            popup.show(relativeTo: anchor, of: sender, preferredEdge: .maxX)
        }
        func closePreview() {
            popover?.close()
            popover = nil
            previewPartID = nil
        }
        func popoverDidClose(_ notification: Notification) {
            if let closed = notification.object as? NSPopover, closed === popover { popover = nil; previewPartID = nil }
        }
        func stop() {
            closePreview()
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
        }
        deinit { stop() }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row), let allocation = rows[row].allocation,
                  let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == "designators" }) else { return 30 }
            let width = max(10, column.width - 36) // padding, spacing, and reserved pencil
            let text = allocation.designators.isEmpty ? "—" : allocation.designators
            // Measure with the same SwiftUI layout used by the cell, including word breaks.
            let measurement = NSHostingView(rootView: Text(text).font(.system(size: 13))
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true).frame(width: width))
            return max(30, ceil(measurement.fittingSize.height) + 12)
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let table, parent.allocations != nil else { return }
            closePreview()
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InventoryRowView() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let key = tableColumn?.identifier.rawValue else { return nil }
            let item = rows[row]
            let part = item.part
            if let allocation = item.allocation {
                if key == "designators" {
                    let save = parent.saveDesignators
                    return hostingCell(InlineTextCell(value: allocation.designators, title: "Designators for \(part.number)", wraps: true, emptyPlaceholder: parent.draftMode ? "" : "—", preview: { [weak self] in self?.previewCell(id: item.id) }) { value in try save?(allocation, value) })
                }
                if key == "quantity" {
                    let save = parent.saveQuantity
                    return hostingCell(InlineTextCell(value: parent.draftMode && allocation.quantity == 0 ? "" : String(allocation.quantity), title: "Quantity for \(part.number)", emptyPlaceholder: parent.draftMode ? "" : "—", preview: { [weak self] in self?.previewCell(id: item.id) }) { value in try save?(allocation, value) })
                }
                if key == "release" {
                    let release = parent.releaseAllocation
                    return hostingCell(ReleaseAllocationButton(title: part.number) { release?(allocation) })
                }
            }
            let text: String
            switch key {
            case "rowNumber": text = item.number.map(String.init) ?? ""
            case "quantity": text = item.allocation?.quantity.formatted() ?? ""
            case "number": text = part.number
            case "manufacturer": text = part.manufacturer
            case "lcsc": text = part.lcsc
            case "description": text = part.description
            case "package": text = part.package
            case "value": text = part.value
            case "tolerance": text = part.tolerance
            case "stock": text = part.stock.formatted()
            default: text = part.storage
            }
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 13, weight: key == "number" ? .medium : .regular)
            label.textColor = key == "stock" ? NSColor(part.stock > 0 ? Theme.green : Theme.muted) : NSColor(key == "storage" ? Theme.muted : .white.opacity(0.88))
            label.lineBreakMode = .byTruncatingTail
            label.alignment = ["stock", "quantity", "rowNumber"].contains(key) ? .right : .left
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label); cell.textField = label
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -9), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            cell.toolTip = text
            return cell
        }
        private func hostingCell<Content: View>(_ content: Content) -> NSTableCellView {
            let cell = NSTableCellView()
            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(host)
            NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: cell.leadingAnchor), host.trailingAnchor.constraint(equalTo: cell.trailingAnchor), host.topAnchor.constraint(equalTo: cell.topAnchor), host.bottomAnchor.constraint(equalTo: cell.bottomAnchor)])
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let id = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
            if previewPartID != id { closePreview() }
            parent.selection = id
        }
    }
}
struct PartTableRow: Identifiable, Equatable {
    var id: String
    var part: Part
    var allocation: Allocation? = nil
    var number: Int? = nil
}
final class InventoryRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .emphasized }
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(Theme.row).setFill(); bounds.fill()
        NSColor.black.withAlphaComponent(0.35).setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
    override func drawSelection(in dirtyRect: NSRect) { NSColor(Theme.selection).setFill(); bounds.fill() }
}
