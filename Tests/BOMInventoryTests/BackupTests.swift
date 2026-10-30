import XCTest
@testable import BOMInventory

final class BackupTests: XCTestCase {
    func testLiteralEnvironmentAndReservedVariables() throws {
        let destination = BackupDestination(repository: "local", environment: "# comment\nAWS_ACCESS_KEY_ID=key\nAWS_SECRET_ACCESS_KEY=value=with spaces\nEMPTY=\nLITERAL=$(touch nope)")
        let values = try destination.variables()
        XCTAssertEqual(values["AWS_SECRET_ACCESS_KEY"], "value=with spaces")
        XCTAssertEqual(values["EMPTY"], "")
        XCTAssertEqual(values["LITERAL"], "$(touch nope)")
        for line in ["missing equals", "1INVALID=value", "RESTIC_PASSWORD=secret", "RESTIC_PASSWORD_COMMAND=command", "RESTIC_REPOSITORY=other"] {
            XCTAssertThrowsError(try BackupDestination(environment: line).variables())
        }
    }

    @MainActor func testConfigurationPersistenceAndValidation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("settings.json")
        let manager = ResticBackup(settingsURL: url)
        let values = [BackupDestination(repository: "s3:https://example.test/bucket", environment: "AWS_ACCESS_KEY_ID=example")]
        try manager.save(values)
        XCTAssertEqual(ResticBackup(settingsURL: url).destinations, values)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try manager.save([BackupDestination()]))
        XCTAssertEqual(manager.destinations, values)
        try manager.save([])
        XCTAssertTrue(ResticBackup(settingsURL: url).destinations.isEmpty)
    }

    @MainActor func testSQLiteSnapshotIsIndependentAndRestorable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteRepository(path: folder.appendingPathComponent("live.sqlite").path)
        var part = Part(); part.number = "Backed up part"; part.stock = 17
        try source.save(part)
        let snapshot = folder.appendingPathComponent("snapshot.sqlite")
        try source.writeBackup(to: snapshot)
        part.stock = 42
        try source.save(part)
        let restored = try SQLiteRepository(path: snapshot.path)
        XCTAssertEqual(try restored.loadParts().first?.stock, 17)
        XCTAssertEqual(try source.loadParts().first?.stock, 42)
    }

    @MainActor func testSyncContinuesAfterFailureAndRecordsOnlySuccess() async throws {
        guard let executable = ResticCommand.executable() else { throw XCTSkip("restic is not installed") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = BackupDestination(repository: folder.appendingPathComponent("good-repo").path)
        let password = "shared-test-password"
        let result = try await Task.detached {
            try ResticCommand.run(executable: executable, destination: good, password: password, command: "init", directory: nil)
        }.value
        XCTAssertEqual(result.status, 0, result.output)
        let manager = ResticBackup(settingsURL: folder.appendingPathComponent("settings.json"))
        try manager.save([BackupDestination(repository: folder.appendingPathComponent("uninitialized-repo").path), good])
        let attachments = folder.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try Data("attachment".utf8).write(to: attachments.appendingPathComponent("example.txt"))
        let store = InventoryStore(repository: try SQLiteRepository(path: folder.appendingPathComponent("live.sqlite").path), attachmentStorage: AttachmentStorage(root: attachments))
        manager.start(password: password, store: store)
        let deadline = Date().addingTimeInterval(30)
        while manager.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(manager.busy)
        XCTAssertNil(manager.destinations[0].lastBackup)
        XCTAssertNotNil(manager.destinations[1].lastBackup)
        XCTAssertTrue(manager.output.contains("Repository 2 of 2"))
        XCTAssertTrue(manager.output.contains("Exit status: 0"))
        XCTAssertEqual(ResticBackup(settingsURL: folder.appendingPathComponent("settings.json")).destinations[1].lastBackup, manager.destinations[1].lastBackup)
    }

    func testLocalResticInitBackupRestoreAndWrongPassword() async throws {
        guard let executable = ResticCommand.executable() else { throw XCTSkip("restic is not installed") }
        try await Task.detached {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let source = folder.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("inventory payload".utf8).write(to: source.appendingPathComponent("inventory.sqlite"))
            let destination = BackupDestination(repository: folder.appendingPathComponent("repo").path)
            let password = "test-only-password"
            let initialized = try ResticCommand.run(executable: executable, destination: destination, password: password, command: "init", directory: nil)
            XCTAssertEqual(initialized.status, 0, initialized.output)
            let backup = try ResticCommand.run(executable: executable, destination: destination, password: password, command: "backup", directory: source)
            XCTAssertEqual(backup.status, 0, backup.output)
            let wrong = try ResticCommand.run(executable: executable, destination: destination, password: "wrong", command: "snapshots", directory: nil)
            XCTAssertNotEqual(wrong.status, 0)
            // The wrapper exposes plain command output without relying on version-specific wording.
            XCTAssertFalse(wrong.output.isEmpty)
            let target = folder.appendingPathComponent("restored")
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--repo", destination.repository, "restore", "latest", "--target", target.path]
            var environment = ProcessInfo.processInfo.environment
            environment["RESTIC_PASSWORD"] = password
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("inventory.sqlite"), encoding: .utf8), "inventory payload")
        }.value
    }
}
