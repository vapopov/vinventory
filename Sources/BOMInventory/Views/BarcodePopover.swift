import SwiftUI
struct BarcodePopover: View {
    var part: Part
    @State private var error: String?
    @State private var copied = false
    var body: some View {
        VStack(spacing: 10) {
            if let image = try? BarcodeLabel.image(for: part) { Image(nsImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fit).frame(width: 540, height: 169) }
            HStack(spacing: 12) {
                Text("Detailed label").foregroundStyle(.white)
                Spacer()
                Button("PNG") { perform { try BarcodeLabel.export(part, pdf: false) } }
                Button("PDF") { perform { try BarcodeLabel.export(part, pdf: true) } }
                Button { perform { try BarcodeLabel.copy(part); copied = true } } label: { Image(systemName: copied ? "checkmark" : "clipboard") }.help("Copy label image")
            }.buttonStyle(.bordered).tint(Theme.yellow).foregroundStyle(Theme.yellow)
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(14).background(Theme.purple)
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}
