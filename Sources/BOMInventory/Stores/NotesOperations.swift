import Foundation

extension InventoryStore {
    func saveNotes(partID: String, purchase: Bool, notes: PartNotes) throws {
        guard notes.images.isEmpty || attachmentStorage != nil else { throw InventoryError.message("Local storage is required for note images.") }
        if purchase {
            guard var item = purchases.first(where: { $0.id == partID }) else { throw InventoryError.message("Purchase item no longer exists.") }
            item.part.notes = notes
            try savePurchase(item)
        } else {
            guard var part = parts.first(where: { $0.id == partID }) else { throw InventoryError.message("Part no longer exists.") }
            part.notes = notes
            try save(part)
        }
    }
}
