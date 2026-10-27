import SwiftUI

struct NiimbotPrintControls: View {
    var part: Part
    @ObservedObject private var printer = NiimbotPrinter.shared
    @AppStorage("niimbot.density") private var density = 3
    @State private var copies = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Niimbot B1 • 50 × 30 mm • 203 dpi").font(.headline)
            HStack {
                Picker("Printer", selection: $printer.selectedID) {
                    if printer.devices.isEmpty { Text("Scan for printers").tag("") }
                    ForEach(printer.devices) { Text($0.name).tag($0.id) }
                }.disabled(printer.busy || printer.connected)
                Button(printer.scanning ? "Scanning…" : "Scan") { printer.scan() }.disabled(printer.busy || printer.scanning || printer.connected)
            }
            HStack {
                Stepper("Copies: \(copies)", value: $copies, in: 1...20)
                Spacer()
                Picker("Density", selection: $density) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 120)
            }.disabled(printer.busy)
            Text(printer.status).font(.caption).foregroundStyle(Theme.muted)
            if let error = printer.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if printer.connected {
                    Button("Disconnect") { printer.disconnect() }.disabled(printer.busy)
                    Spacer()
                    Button("Print label") { Task { await printer.printLabel(part, copies: copies, density: density) } }.disabled(printer.busy)
                } else {
                    Button("Connect") { printer.connect() }.disabled(printer.busy || printer.devices.isEmpty)
                }
                if printer.busy { ProgressView().controlSize(.small) }
            }.buttonStyle(.bordered)
        }.padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 4)).frame(width: 400)
    }
}
