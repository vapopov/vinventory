import Foundation

extension InventoryStore {
    func saveProjectNotes(projectName: String, notes: PartNotes) throws {
        guard let project = projects.first(where: { $0.name.caseInsensitiveCompare(projectName) == .orderedSame }) else { throw InventoryError.message("Project no longer exists.") }
        guard notes.images.isEmpty || attachmentStorage != nil else { throw InventoryError.message("Local storage is required for note images.") }
        var previous = Part()
        previous.id = project.notesAttachmentID ?? "project-" + UUID().uuidString
        previous.notes = project.notes
        var updated = previous; updated.notes = notes
        let prepared = try attachmentStorage?.prepare(updated)
        updated = prepared?.part ?? updated
        do { try repository.saveProjectNotes(name: project.name, attachmentID: updated.id, notes: updated.notes) }
        catch { prepared?.rollback(); throw error }
        do { try attachmentStorage?.removeReplaced(previous: previous, current: updated) }
        catch { self.error = "Project notes saved, but old images could not be removed: \(error.localizedDescription)" }
        try reload()
    }
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
