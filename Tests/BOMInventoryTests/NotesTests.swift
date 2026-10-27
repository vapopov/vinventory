import XCTest
import AppKit
@testable import BOMInventory

final class NotesTests: XCTestCase {
    @MainActor func testFormattedTextAndImageRoundTripAndManagedCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AttachmentStorage(root: root)
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"), attachmentStorage: storage)
        var part = Part(); part.number = "Notes test"
        try store.save(part)
        let document = NSMutableAttributedString(string: "Bold note\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 20, height: 20).fill(); image.unlockFocus()
        let wrapper = FileWrapper(regularFileWithContents: try XCTUnwrap(image.tiffRepresentation))
        wrapper.preferredFilename = "test.tiff"
        document.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        let draft = AttachmentDraft()
        let note = try NotesDocument.save(document, draft: draft)
        XCTAssertFalse(note.images.isEmpty)
        try store.saveNotes(partID: part.id, purchase: false, notes: note)
        let saved = try XCTUnwrap(store.parts.first).notes
        XCTAssertTrue(saved.images.values.allSatisfy { $0.hasPrefix(root.path) })
        draft.discard()
        let loaded = try NotesDocument.load(saved)
        XCTAssertEqual(loaded.string, document.string)
        let font = try XCTUnwrap(loaded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertNotNil(loaded.attribute(.attachment, at: loaded.length - 1, effectiveRange: nil))
        try store.reload()
        XCTAssertEqual(store.parts.first?.notes, saved)
        try store.saveNotes(partID: part.id, purchase: false, notes: PartNotes())
        XCTAssertTrue(saved.images.values.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
        try store.saveNotes(partID: part.id, purchase: false, notes: PartNotes(text: "Existing note"))
        let purchaseDraft = AttachmentDraft()
        var purchase = PurchaseItem(); purchase.part.number = part.number
        purchase.part.notes = try NotesDocument.save(document, draft: purchaseDraft)
        try store.savePurchase(purchase)
        purchaseDraft.discard()
        try store.receivePurchases(ids: [purchase.id])
        let received = try XCTUnwrap(store.parts.first).notes
        XCTAssertFalse(received.images.isEmpty)
        XCTAssertTrue(received.images.values.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        XCTAssertEqual(try NotesDocument.load(received).string, "Existing note\n\n" + document.string)
    }
    @MainActor func testReceivingMergesNotesAndOldPartsDecodeWithoutNotes() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var part = Part(); part.number = "MPN"; part.stock = 1; part.notes.text = "Inventory note"
        try store.save(part)
        var item = PurchaseItem(); item.part.number = "MPN"; item.part.notes.text = "Purchase note"
        try store.savePurchase(item)
        try store.receivePurchases(ids: [item.id])
        let saved = try XCTUnwrap(store.parts.first)
        XCTAssertEqual(try NotesDocument.load(saved.notes).string, "Inventory note\n\nPurchase note")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json.removeValue(forKey: "notes")
        XCTAssertTrue(try JSONDecoder().decode(Part.self, from: JSONSerialization.data(withJSONObject: json)).notes.isEmpty)
    }
}
