import AVFoundation
import Combine
import Vision

final class BarcodeCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var error: String?
    @Published var code: String?
    private let queue = DispatchQueue(label: "com.local.BOMInventory.barcode-camera")
    private var enabled = false
    struct CameraOption: Identifiable { var id: String; var name: String }
    @Published var cameras: [CameraOption] = []
    @Published var selectedCameraID = ""
    private let preferences: UserDefaults
    private static let preferenceKey = "barcodeScanner.preferredCameraID"
    private var activeCameraID: String?
    private var observers: [NSObjectProtocol] = []

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        super.init()
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    static func resolvedCameraID(preferred: String?, available: [String], defaultID: String?) -> String? {
        if let preferred, available.contains(preferred) { return preferred }
        if let defaultID, available.contains(defaultID) { return defaultID }
        return available.first
    }
    func selectCamera(_ id: String) {
        guard cameras.contains(where: { $0.id == id }) else { return }
        preferences.set(id, forKey: Self.preferenceKey)
        selectedCameraID = id
        error = nil
        configure()
    }
    private var accepting = false
    private var lastFrameTime = 0.0

    func start() {
        accepting = true
        if observers.isEmpty {
            for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.configure()
                })
            }
        }
        queue.async { self.enabled = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.configure() } else { self.fail("Camera access was denied. Enable it in System Settings → Privacy & Security → Camera.") }
            }
        default: fail("Camera access is unavailable. Enable it in System Settings → Privacy & Security → Camera.")
        }
    }
    func stop() {
        accepting = false
        queue.async {
            self.enabled = false
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    private func configure() {
        queue.async {
            guard self.enabled else { return }
            do {
                let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
                let options = devices.map { CameraOption(id: $0.uniqueID, name: $0.localizedName) }
                let chosen = Self.resolvedCameraID(preferred: self.preferences.string(forKey: Self.preferenceKey), available: devices.map(\.uniqueID), defaultID: AVCaptureDevice.default(for: .video)?.uniqueID)
                DispatchQueue.main.async {
                    self.cameras = options
                    self.selectedCameraID = chosen ?? ""
                    self.error = nil
                }
                guard let device = devices.first(where: { $0.uniqueID == chosen }) else {
                    if self.session.isRunning { self.session.stopRunning() }
                    self.activeCameraID = nil
                    throw InventoryError.message("No camera found. Connect a camera to scan.")
                }
                if self.activeCameraID != device.uniqueID {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.isRunning { self.session.stopRunning() }
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.sessionPreset = .high
                    let previousInputs = self.session.inputs
                    previousInputs.forEach { self.session.removeInput($0) }
                    guard self.session.canAddInput(input) else {
                        previousInputs.filter { self.session.canAddInput($0) }.forEach { self.session.addInput($0) }
                        throw InventoryError.message("Could not use this camera. Choose another camera.")
                    }
                    self.session.addInput(input)
                    if self.session.outputs.isEmpty {
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        guard self.session.canAddOutput(output) else { throw InventoryError.message("This camera cannot provide video for scanning.") }
                        self.session.addOutput(output)
                        output.setSampleBufferDelegate(self, queue: self.queue)
                    }
                    self.activeCameraID = device.uniqueID
                    self.lastFrameTime = 0
                }
                self.session.startRunning()
            } catch { self.fail(error.localizedDescription) }
        }
    }
    private func fail(_ message: String) { DispatchQueue.main.async { self.error = message } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard enabled, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastFrameTime >= 0.2 else { return }
        lastFrameTime = time
        do {
            guard let value = try Self.detectBarcode(in: buffer) else { return }
            DispatchQueue.main.async {
                guard self.accepting, self.code == nil else { return }
                self.code = value
                self.stop()
            }
        } catch { fail("Could not analyze camera frames: " + error.localizedDescription) }
    }
    static func detectBarcode(in buffer: CVPixelBuffer) throws -> String? {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
        return request.results?.compactMap(\.payloadStringValue).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
