import SwiftUI
import AppKit

/// Shared part details for the PARTS inspector and the reusable Part Preview popup.
struct PartSummaryView: View {
    @Environment(\.inventoryNavigation) private var navigation
    var part: Part
    var available: Int
    var allocated: Int
    var edit: () -> Void
    var beforeNavigate: () -> Void = {}
    @State private var barcode = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(part.manufacturer.isEmpty ? "Manufacturer unspecified" : part.manufacturer).foregroundStyle(Theme.muted).font(.system(size: 16, weight: .medium))
                    Text(part.number).font(.system(size: 26, weight: .bold)).textSelection(.enabled)
                    LabelChips(labels: part.labels)
                }
                Spacer()
                PartImageThumbnail(image: part.image, partNumber: part.number)
            }
            Text(part.description.isEmpty ? "No description" : part.description).font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
            HStack {
                Text([part.value, part.tolerance.isEmpty ? "" : "Tolerance \(part.tolerance)", part.package].filter { !$0.isEmpty }.joined(separator: "  •  ")).foregroundStyle(Theme.muted)
                Spacer()
                ToolButton(symbol: "qrcode", title: "Show barcode label") { barcode.toggle() }.popover(isPresented: $barcode) { BarcodePopover(part: part) }
                Button("Datasheet") { if let url = try? DatasheetReference.url(for: part.datasheet) { NSWorkspace.shared.open(url) } }.buttonStyle(.plain).foregroundStyle(Theme.yellow).padding(9).background(Theme.raised).disabled(part.datasheet.isEmpty).help(part.datasheet.hasPrefix("/") ? "Open local PDF" : "Open datasheet in browser")
            }
            HStack(spacing: 8) { metric("On-hand", part.stock); metric("Available", available, color: Theme.green); metric("Allocated", allocated) }
            HStack { Image(systemName: "archivebox"); if part.storage.isEmpty { Text("No storage assigned") } else { DestinationLink(title: part.storage, destination: "storage") { beforeNavigate(); navigation.storage(part.storage) } }; Spacer(); Button("Edit details", action: edit).buttonStyle(.plain).foregroundStyle(Theme.yellow) }.font(.system(size: 12)).foregroundStyle(Theme.muted)
        }.padding(24)
    }
    private func metric(_ title: String, _ value: Int, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).foregroundStyle(Theme.muted); Text(value.formatted()).font(.system(size: 20, weight: .medium)).foregroundStyle(color).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(Theme.selection.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
    }
}
