import AppKit
import CoreBluetooth
import Combine

// CoreBluetooth is explicitly configured with queue .main, so all delegate calls
// share the UI actor. Remove @preconcurrency once the SDK annotates these delegate
// protocols, or move to isolated conformances when the package adopts Swift 6.
@MainActor final class NiimbotPrinter: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let shared = NiimbotPrinter()
    static let serviceID = CBUUID(string: "e7810a71-73ae-499d-8c15-faa9aef0c3f2")
    static let characteristicID = CBUUID(string: "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f")
    struct Device: Identifiable { var id: String; var name: String; var peripheral: CBPeripheral }
    @Published private(set) var devices: [Device] = []
    @Published var selectedID = UserDefaults.standard.string(forKey: "niimbot.printerID") ?? ""
    @Published private(set) var status = "Connect your Niimbot B1"
    @Published private(set) var error: String?
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var scanning = false
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var decoder = NiimbotFrameDecoder()
    private var replies: [(Int, NiimbotFrame)] = []
    private var replyNumber = 0
    private var highestReceivedRow: Int?
    private var writePending = false
    private var writeError: Error?
    private var pendingScan = false
    private var generation = UUID()

    func scan() {
        guard !busy else { return }
        error = nil; pendingScan = true
        if central.state == .poweredOn { beginScan() }
        else { centralManagerDidUpdateState(central) }
    }
    private func beginScan() {
        pendingScan = false; scanning = true
        status = "Searching for B1 printers…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if scanning { central.stopScan(); scanning = false; status = devices.isEmpty ? "No B1 found. Turn it on and close other printer apps." : "Select your B1 and connect." }
        }
    }
    func connect() {
        guard !busy, let device = devices.first(where: { $0.id == selectedID }) else { return }
        central.stopScan(); scanning = false; pendingScan = false
        if let old = peripheral, old.identifier != device.peripheral.identifier { central.cancelPeripheralConnection(old) }
        generation = UUID(); let token = generation
        peripheral = device.peripheral; characteristic = nil; connected = false
        decoder = NiimbotFrameDecoder(); replies = []; error = nil; busy = true
        status = "Connecting to \(device.name)…"
        peripheral?.delegate = self
        central.connect(device.peripheral)
        Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            if generation == token && busy && !connected { fail("Connection timed out. Close the Niimbot phone app and try again.") }
        }
    }
    func disconnect() {
        guard !busy else { return }
        generation = UUID(); central.stopScan(); scanning = false; pendingScan = false
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        characteristic = nil; connected = false; status = "Disconnected"
    }
    private func fail(_ message: String) {
        error = message; status = "Printer unavailable"; connected = false; busy = false
        generation = UUID(); characteristic = nil
        if let peripheral, peripheral.state != .disconnected { central.cancelPeripheralConnection(peripheral) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if pendingScan { beginScan() }
        case .unauthorized: fail("Allow Bluetooth access in System Settings → Privacy & Security → Bluetooth.")
        case .poweredOff: fail("Bluetooth is turned off. Turn it on to connect the printer.")
        case .unsupported: fail("Bluetooth Low Energy is not supported on this Mac.")
        case .resetting: status = "Bluetooth is resetting…"
        default: status = "Waiting for Bluetooth…"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.uppercased().hasPrefix("B1") else { return }
        let id = peripheral.identifier.uuidString
        if !devices.contains(where: { $0.id == id }) { devices.append(Device(id: id, name: name, peripheral: peripheral)) }
        if !devices.contains(where: { $0.id == selectedID }) { selectedID = id }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        status = "Discovering printer service…"; peripheral.discoverServices([Self.serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        fail(error?.localizedDescription ?? "Could not connect to the printer.")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        generation = UUID()
        characteristic = nil; connected = false
        if busy { self.error = "Printer disconnected. Check the label before retrying." }
        busy = false; status = "Disconnected"
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else { fail(error?.localizedDescription ?? "Niimbot service was not found."); return }
        peripheral.discoverCharacteristics([Self.characteristicID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let channel = service.characteristics?.first(where: { $0.uuid == Self.characteristicID }),
              channel.properties.contains(.notify), channel.properties.contains(.writeWithoutResponse) || channel.properties.contains(.write) else { fail(error?.localizedDescription ?? "Printer has no supported Bluetooth channel."); return }
        characteristic = channel; peripheral.setNotifyValue(true, for: channel)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor channel: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, channel.uuid == Self.characteristicID else { return }
        guard error == nil, channel.isNotifying else { fail(error?.localizedDescription ?? "Could not enable printer notifications."); return }
        let token = generation
        Task {
            do {
                status = "Identifying printer…"
                _ = try? await command(0xa5, [1], response: 0xb5, timeout: 1)
                let model = try await command(0x40, [8], response: 0x48)
                guard model.payload.count >= 2, Int(model.payload[0]) << 8 | Int(model.payload[1]) == 4096 else { throw InventoryError.message("This print path supports Niimbot B1 (203 dpi), not B1 Pro or other models.") }
                _ = try? await command(0xa5, [1], response: 0xb5, timeout: 1)
                for sub: UInt8 in [8, 11, 13, 10, 7, 3, 12, 9] { _ = try? await command(0x40, [sub], response: nil, timeout: 0.6) }
                _ = try? await command(0xdc, [4], response: 0xd9, timeout: 1)
                guard generation == token else { return }
                connected = true; busy = false; status = "Niimbot B1 connected • 203 dpi"
                UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "niimbot.printerID")
            } catch { if generation == token { fail(error.localizedDescription) } }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor channel: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, channel.uuid == Self.characteristicID else { return }
        guard error == nil, let data = channel.value else { return }
        for frame in decoder.append(data) {
            if frame.command == 0xd3, frame.payload.count >= 2 {
                let row = Int(frame.payload[0]) << 8 | Int(frame.payload[1])
                highestReceivedRow = max(highestReceivedRow ?? -1, row)
            }
            replyNumber += 1; replies.append((replyNumber, frame))
            if replies.count > 256 { replies.removeFirst(replies.count - 256) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor channel: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, channel.uuid == Self.characteristicID else { return }
        writeError = error; writePending = false
    }
    private func write(_ bytes: Data) async throws {
        guard let peripheral, peripheral.state == .connected, let channel = characteristic else { throw InventoryError.message("Printer is disconnected.") }
        let token = generation
        let type: CBCharacteristicWriteType = channel.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let limit = peripheral.maximumWriteValueLength(for: type)
        guard limit > 0 else { throw InventoryError.message("Invalid Bluetooth write size.") }
        for offset in stride(from: 0, to: bytes.count, by: limit) {
            try Task.checkCancellation()
            let deadline = Date().addingTimeInterval(5)
            if type == .withoutResponse {
                while !peripheral.canSendWriteWithoutResponse {
                    guard Date() < deadline, generation == token, peripheral.state == .connected else { throw InventoryError.message("Bluetooth write stalled.") }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            guard generation == token, peripheral.state == .connected else { throw InventoryError.message("Printer disconnected during upload.") }
            writePending = type == .withResponse; writeError = nil
            peripheral.writeValue(bytes.subdata(in: offset..<min(offset + limit, bytes.count)), for: channel, type: type)
            while writePending {
                guard Date() < deadline, generation == token, peripheral.state == .connected else { throw InventoryError.message("Bluetooth write acknowledgement timed out.") }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            if let writeError { throw writeError }
            // B1 needs pacing even when CoreBluetooth has remaining transmit credits.
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    private func command(_ code: UInt8, _ payload: [UInt8], response: UInt8?, timeout: TimeInterval = 2) async throws -> NiimbotFrame {
        let baseline = replyNumber, token = generation
        try await write(NiimbotFrame(command: code, payload: payload).encoded())
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard token == generation, peripheral?.state == .connected else { throw InventoryError.message("Printer disconnected.") }
            if let answer = replies.first(where: { $0.0 > baseline && (response == nil ? $0.1.command != 0xd3 : $0.1.command == response) }) { return answer.1 }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw InventoryError.message(String(format: "No printer acknowledgement for command 0x%02X. Check paper, lid, and Bluetooth connection.", code))
    }
    func printLabel(_ part: Part, copies: Int = 1, density: Int = 3) async {
        guard connected, !busy else { return }
        guard (1...5).contains(density), (1...20).contains(copies) else { error = "Choose density 1–5 and copies 1–20."; return }
        busy = true; error = nil; var started = false
        let token = generation
        defer { if generation == token { busy = false } }
        do {
            let raster = try NiimbotRaster.label(for: part)
            status = "Configuring label…"
            _ = try await command(0x21, [UInt8(density)], response: 0x31)
            _ = try await command(0x23, [1], response: 0x33)
            started = true
            _ = try await command(0x01, [0, UInt8(copies), 0, 0, 0, 0, 0], response: 0x02)
            _ = try await command(0x03, [1], response: 0x04)
            _ = try await command(0x13, NiimbotRaster.pageSize(copies: copies), response: 0x14)
            highestReceivedRow = nil
            let frames = try raster.rowFrames()
            for (index, frame) in frames.enumerated() {
                status = "Sending label • \((index + 1) * 100 / frames.count)%"
                try await write(frame.encoded())
            }
            _ = try await command(0xe3, [1], response: 0xe4, timeout: 10)
            if let highestReceivedRow, highestReceivedRow < raster.height - 1 {
                throw InventoryError.message("Printer only confirmed image row \(highestReceivedRow + 1) of \(raster.height). The label may be incomplete.")
            }
            status = "Waiting for print confirmation…"
            let deadline = Date().addingTimeInterval(25)
            var confirmed = false
            while Date() < deadline {
                if let reply = try? await command(0xa3, [1], response: 0xb3, timeout: 0.9), reply.payload.count >= 4 {
                    let pages = Int(reply.payload[0]) << 8 | Int(reply.payload[1])
                    status = "Printed \(pages) of \(copies) labels"
                    if pages >= copies { confirmed = true; break }
                }
                guard connected else { throw InventoryError.message("Printer disconnected before print confirmation.") }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            started = false // PrintEnd is attempted exactly once, even on a failed job.
            _ = try await command(0xf3, [1], response: 0xf4, timeout: 2.5)
            guard confirmed else { throw InventoryError.message("Print was not confirmed. Check the label before retrying; it may already have printed.") }
            status = "Printed \(copies) label\(copies == 1 ? "" : "s") • confirmed by B1"
        } catch {
            guard generation == token else { return }
            if started { _ = try? await command(0xf3, [1], response: 0xf4, timeout: 2.5) }
            self.error = error.localizedDescription + " Check the label before retrying."
            status = "Print not confirmed"
        }
    }
}
