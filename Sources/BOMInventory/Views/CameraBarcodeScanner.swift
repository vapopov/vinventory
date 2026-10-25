import SwiftUI
import AVFoundation
import AppKit

struct CameraBarcodeScanner: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = BarcodeCamera()
    var found: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Scan barcode").font(.headline); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Hold the part’s QR code or barcode in front of the camera.").foregroundStyle(Theme.muted)
            Picker("Camera", selection: Binding(get: { camera.selectedCameraID }, set: { camera.selectCamera($0) })) {
                if camera.cameras.isEmpty { Text("No camera available").tag("") }
                ForEach(camera.cameras) { option in Text(option.name).tag(option.id) }
            }.disabled(camera.cameras.isEmpty)
            CameraPreview(session: camera.session).frame(width: 560, height: 340).background(.black)
            if let error = camera.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.padding(20).frame(width: 600).background(Theme.panel)
            .onAppear { camera.start() }.onDisappear { camera.stop() }
            .onReceive(camera.$code.compactMap { $0 }) { code in found(code); dismiss() }
    }
}
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    final class PreviewView: NSView {
        private let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
