import Foundation

struct PurchaseAssignment: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var project: String
    var quantity: Int
    var designators = ""
}

/// part.stock is the quantity planned for purchase, not physical inventory.
struct PurchaseItem: Identifiable, Codable, Equatable {
    var part = Part()
    var assignments: [PurchaseAssignment] = []
    var id: String { part.id }
    init() { part.stock = 1 }
}
