import Foundation
import Combine

struct BackupDestination: Codable, Identifiable, Equatable {
    var id = UUID()
    var repository = ""
    var environment = ""
    var lastBackup: Date?

    func variables() throws -> [String: String] {
        var result: [String: String] = [:]
        for line in environment.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { throw InventoryError.message("Use ENV_NAME=ENV_VALUE, one variable per line.") }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw InventoryError.message("Invalid environment variable name: \(name)") }
            guard !["RESTIC_PASSWORD", "RESTIC_PASSWORD_FILE", "RESTIC_PASSWORD_COMMAND", "RESTIC_REPOSITORY", "RESTIC_REPOSITORY_FILE"].contains(name) else {
                throw InventoryError.message("Set the repository in Destination and enter its password when prompted; do not set \(name) here.")
            }
            result[name] = String(line[line.index(after: separator)...])
        }
        return result
    }
}

struct ResticResult: Sendable { let status: Int32; let output: String }

enum ResticCommand {
    static func executable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let directories = (environment["PATH"] ?? "").components(separatedBy: ":") + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        return directories.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0).appendingPathComponent("restic") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func run(executable: URL, destination: BackupDestination, password: String, command: String, directory: URL?) throws -> ResticResult {
        var environment = ProcessInfo.processInfo.environment
        for name in ["RESTIC_PASSWORD", "RESTIC_PASSWORD_FILE", "RESTIC_PASSWORD_COMMAND", "RESTIC_REPOSITORY", "RESTIC_REPOSITORY_FILE"] { environment.removeValue(forKey: name) }
        environment.merge(try destination.variables()) { _, new in new }
        environment["RESTIC_PASSWORD"] = password
        let process = Process()
        process.executableURL = executable
        process.environment = environment
        process.arguments = ["--repo", destination.repository, command] + (command == "backup" ? ["--tag", "bom-inventory", "."] : [])
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ResticResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

@MainActor final class ResticBackup: ObservableObject {
    static let shared = ResticBackup()
    @Published private(set) var destinations: [BackupDestination] = []
    @Published private(set) var executable: URL?
    @Published private(set) var busy = false
    @Published private(set) var output = ""
    @Published var error: String?
    private let settingsURL: URL

    init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BOMInventory/backup-settings.json")
        if FileManager.default.fileExists(atPath: self.settingsURL.path) {
            do { destinations = try JSONDecoder().decode([BackupDestination].self, from: Data(contentsOf: self.settingsURL)) }
            catch { self.error = "Cannot load backup configuration: \(error.localizedDescription)" }
        }
        refresh()
    }
    func refresh() { executable = ResticCommand.executable() }
    func save(_ values: [BackupDestination]) throws {
        guard !busy else { throw InventoryError.message("Wait for the current backup operation to finish.") }
        for value in values {
            guard !value.repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InventoryError.message("Enter a destination for every repository.") }
            _ = try value.variables()
        }
        try persist(values)
        destinations = values
    }
    private func persist(_ values: [BackupDestination]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }
    func start(password: String, initializing destinationID: UUID? = nil, store: InventoryStore) {
        guard !busy, !password.isEmpty else { return }
        refresh()
        guard let executable else { error = "restic must be installed. It is required for the backup feature."; return }
        let targets = destinationID.map { id in destinations.filter { $0.id == id } } ?? destinations
        guard !targets.isEmpty else { error = "Configure at least one repository first."; return }
        busy = true
        output = "Preparing \(destinationID == nil ? "backup" : "repository initialization")…\n"
        Task {
            var staging: URL?
            defer {
                if let staging { try? FileManager.default.removeItem(at: staging) }
                busy = false
            }
            do {
                if destinationID == nil {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BOMInventory-backup-\(UUID().uuidString)", isDirectory: true)
                    staging = folder
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    guard let repository = store.repository as? SQLiteRepository else { throw InventoryError.message("This inventory does not support SQLite backups.") }
                    try repository.writeBackup(to: folder.appendingPathComponent("inventory.sqlite"))
                    if let attachments = store.attachmentStorage, FileManager.default.fileExists(atPath: attachments.root.path) {
                        try FileManager.default.copyItem(at: attachments.root, to: folder.appendingPathComponent("Attachments"))
                    }
                }
                for (index, destination) in targets.enumerated() {
                    let command = destinationID == nil ? "backup" : "init"
                    output += "\nRepository \(index + 1) of \(targets.count): restic \(command)\n"
                    let directory = staging
                    do {
                        let result = try await Task.detached(priority: .utility) {
                            try ResticCommand.run(executable: executable, destination: destination, password: password, command: command, directory: directory)
                        }.value
                        output += result.output + "\nExit status: \(result.status)\n"
                        if result.status == 0 && command == "backup", let position = destinations.firstIndex(where: { $0.id == destination.id }) {
                            destinations[position].lastBackup = Date()
                            try persist(destinations)
                        }
                    } catch { output += "Failed: \(error.localizedDescription)\n" }
                }
            } catch { output += "Failed: \(error.localizedDescription)\n"; self.error = error.localizedDescription }
        }
    }
}
