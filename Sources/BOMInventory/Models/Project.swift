import Foundation

struct Project: Identifiable, Equatable {
    var name: String
    var description: String
    var id: String { name }
    func contains(_ allocation: Allocation) -> Bool {
        allocation.project.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
    }
}
