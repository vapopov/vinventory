import XCTest
import AppKit
@testable import BOMInventory

final class ProjectNotesTests: XCTestCase {
    @MainActor func testProjectNotesPersistThroughRenamesAndDoNotReturnAfterDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("inventory.sqlite").path
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "Controller")
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Other", description: "")
        let draft = AttachmentDraft()
        let source = NSAttributedString(string: #"Board notes \(V = IR\)"#, attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        try store.saveProjectNotes(projectName: "board", notes: NotesDocument.save(source, draft: draft))
        let saved = try XCTUnwrap(store.projects.first { $0.name == "Board" })
        XCTAssertFalse(saved.notes.isEmpty)
        XCTAssertTrue(saved.notesAttachmentID?.hasPrefix("project-") == true)
        XCTAssertTrue(store.projects.first { $0.name == "Other" }?.notes.isEmpty == true)
        _ = try store.saveCatalog(kind: .project, originalName: "Board", name: "Board Revision B", description: "Updated")
        let reopened = InventoryStore(repository: try SQLiteRepository(path: path))
        let renamed = try XCTUnwrap(reopened.projects.first { $0.name == "Board Revision B" })
        XCTAssertEqual(renamed.notes, saved.notes)
        XCTAssertEqual(renamed.notesAttachmentID, saved.notesAttachmentID)
        XCTAssertEqual(try NotesDocument.load(renamed.notes).string, source.string)
        try reopened.deleteCatalog(kind: .project, name: renamed.name)
        _ = try reopened.saveCatalog(kind: .project, originalName: nil, name: renamed.name, description: "New project")
        XCTAssertTrue(reopened.projects.first { $0.name == renamed.name }?.notes.isEmpty == true)
        XCTAssertThrowsError(try reopened.saveProjectNotes(projectName: "Missing", notes: PartNotes(text: "note")))
    }
    @MainActor func testProjectNoteImagesAreManagedAndCleanedOnClearAndDelete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"), attachmentStorage: AttachmentStorage(root: root))
        _ = try store.saveCatalog(kind: .project, originalName: nil, name: "Board", description: "")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = FileWrapper(regularFileWithContents: png); image.preferredFilename = "board.png"
        let document = NSAttributedString(attachment: NSTextAttachment(fileWrapper: image))
        let draft = AttachmentDraft()
        try store.saveProjectNotes(projectName: "Board", notes: NotesDocument.save(document, draft: draft))
        draft.discard()
        let saved = try XCTUnwrap(store.projects.first).notes
        XCTAssertFalse(saved.images.isEmpty)
        XCTAssertTrue(saved.images.values.allSatisfy { $0.hasPrefix(root.path) && FileManager.default.fileExists(atPath: $0) })
        XCTAssertNotNil(try NotesDocument.load(saved).attribute(.attachment, at: 0, effectiveRange: nil))
        try store.saveProjectNotes(projectName: "Board", notes: PartNotes())
        XCTAssertTrue(saved.images.values.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
        let nextDraft = AttachmentDraft()
        try store.saveProjectNotes(projectName: "Board", notes: NotesDocument.save(document, draft: nextDraft))
        let images = try XCTUnwrap(store.projects.first).notes.images
        try store.deleteCatalog(kind: .project, name: "Board")
        XCTAssertTrue(images.values.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }
}
