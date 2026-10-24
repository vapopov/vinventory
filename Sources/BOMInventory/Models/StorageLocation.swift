import Foundation

/// Locations follow saved part assignments; nil represents unassigned parts.
struct StorageLocation: Identifiable, Equatable {
    var name: String?
    var description: String
    var id: String { name.map { "named:\($0)" } ?? "unassigned" }
    var displayName: String { name ?? "(no storage)" }
    func contains(_ part: Part) -> Bool {
        guard let name else { return part.storage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return part.storage.caseInsensitiveCompare(name) == .orderedSame
    }
}

enum InventorySection: String, CaseIterable {
    case parts = "PARTS"
    case storage = "STORAGE"
}
