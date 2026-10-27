import SwiftUI
struct BarcodePopover: View {
    var part: Part
    @State private var error: String?
    @State private var copied = false
    @State private var printerOptions = false
    @ObservedObject private var printer = NiimbotPrinter.shared
    @AppStorage("niimbot.density") private var density = 3
    var body: some View {
        VStack(spacing: 10) {
            if let image = try? BarcodeLabel.image(for: part) { Image(nsImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fit).frame(width: 400, height: 240) }
            HStack(spacing: 12) {
                Text("50 × 30 mm • 300 dpi").foregroundStyle(.white)
                Spacer()
                Button("PNG") { perform { try BarcodeLabel.export(part, pdf: false) } }
                Button {
                    if printer.connected { Task { await printer.printLabel(part, density: density) } }
                    else { printerOptions = true }
                } label: { Image(systemName: "printer") }.disabled(printer.busy).help("Print on Niimbot B1").accessibilityLabel("Print on Niimbot B1")
                if printer.connected { Button { printerOptions.toggle() } label: { Image(systemName: "gearshape") }.help("Printer settings") }
                Button("PDF") { perform { try BarcodeLabel.export(part, pdf: true) } }
                Button { perform { try BarcodeLabel.copy(part); copied = true } } label: { Image(systemName: copied ? "checkmark" : "clipboard") }.help("Copy label image")
            }.buttonStyle(.bordered).tint(Theme.yellow).foregroundStyle(Theme.yellow)
            if printerOptions { NiimbotPrintControls(part: part) }
            else if printer.connected || printer.error != nil {
                Text(printer.error ?? printer.status).font(.caption).foregroundStyle(printer.error == nil ? Color.white : .red).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .background(Theme.purple)
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}
