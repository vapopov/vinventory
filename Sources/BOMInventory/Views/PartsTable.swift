import SwiftUI
import AppKit
// AppKit provides exact row selection colors and desktop column resizing.
struct PartsTable: NSViewRepresentable {
    var parts: [Part]
    @Binding var selection: String?
    var preview: ((Part, PartPreviewDismissAction) -> AnyView)? = nil
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
        table.intercellSpacing = NSSize(width: 1, height: 1)
        table.backgroundColor = NSColor(Theme.row)
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.style = .plain
        table.target = context.coordinator
        table.action = #selector(Coordinator.rowClicked(_:))
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observeScrolling(scroll.contentView)
        let columns: [(String, String, CGFloat)] = [("number", "Part Number", 160), ("manufacturer", "Manufacturer", 150), ("description", "Description", 220), ("package", "Package", 90), ("value", "Value", 80), ("tolerance", "Tolerance", 85), ("stock", "Stock Balance", 110), ("storage", "Storage", 120)]
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
        let changed = coordinator.parent.parts != parts
        let rowsChanged = coordinator.parent.parts.map(\.id) != parts.map(\.id)
        if rowsChanged { coordinator.closePreview() }
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        coordinator.updating = true
        if changed || table.numberOfRows != parts.count { table.reloadData() }
        if let index = parts.firstIndex(where: { $0.id == selection }) {
            if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        } else { table.deselectAll(nil) }
        coordinator.updating = false
        if let id = coordinator.previewPartID, !parts.contains(where: { $0.id == id }) { coordinator.closePreview() }
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSPopoverDelegate {
        var parent: PartsTable
        weak var table: NSTableView?
        var updating = false
        var previewPartID: String?
        private var popover: NSPopover?
        private var scrollObserver: NSObjectProtocol?
        init(_ parent: PartsTable) { self.parent = parent }
        func observeScrolling(_ clip: NSClipView) {
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.closePreview() }
        }
        @objc func rowClicked(_ sender: NSTableView) {
            guard let builder = parent.preview, parent.parts.indices.contains(sender.clickedRow) else { return }
            let row = sender.clickedRow
            let part = parent.parts[row]
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
            previewPartID = part.id
            let cell = sender.frameOfCell(atColumn: 0, row: row).intersection(sender.visibleRect)
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
        func numberOfRows(in tableView: NSTableView) -> Int { parent.parts.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InventoryRowView() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.parts.indices.contains(row), let key = tableColumn?.identifier.rawValue else { return nil }
            let part = parent.parts[row]
            let text: String
            switch key {
            case "number": text = part.number
            case "manufacturer": text = part.manufacturer
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
            label.alignment = key == "stock" ? .right : .left
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label); cell.textField = label
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -9), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            cell.toolTip = text
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let id = parent.parts.indices.contains(table.selectedRow) ? parent.parts[table.selectedRow].id : nil
            if previewPartID != id { closePreview() }
            parent.selection = id
        }
    }
}
private final class InventoryRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .emphasized }
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(Theme.row).setFill(); bounds.fill()
        NSColor.black.withAlphaComponent(0.35).setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
    override func drawSelection(in dirtyRect: NSRect) { NSColor(Theme.selection).setFill(); bounds.fill() }
}
