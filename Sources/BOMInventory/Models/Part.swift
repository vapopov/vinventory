import Foundation
struct Part: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var number = ""
    var manufacturer = ""
    var labels: [String] = []
    var tolerance = ""
    var description = ""
    var package = ""
    var value = ""
    var storage = ""
    var datasheet = ""
    var barcode = UUID().uuidString
    var stock = 0
    var image: PartImage?

    init() {}
    private enum CodingKeys: String, CodingKey {
        case id, number, manufacturer, labels, tolerance, description, package, value, storage, datasheet, barcode, stock, image
    }
    private enum LegacyKeys: String, CodingKey { case category }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(String.self, forKey: .id)
        number = try data.decode(String.self, forKey: .number)
        manufacturer = try data.decode(String.self, forKey: .manufacturer)
        if let saved = try data.decodeIfPresent([String].self, forKey: .labels) {
            labels = saved
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let category = try legacy.decodeIfPresent(String.self, forKey: .category) ?? ""
            labels = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [category]
        }
        tolerance = try data.decodeIfPresent(String.self, forKey: .tolerance) ?? ""
        description = try data.decode(String.self, forKey: .description)
        package = try data.decode(String.self, forKey: .package)
        value = try data.decode(String.self, forKey: .value)
        storage = try data.decode(String.self, forKey: .storage)
        datasheet = try data.decode(String.self, forKey: .datasheet)
        barcode = try data.decode(String.self, forKey: .barcode)
        stock = try data.decode(Int.self, forKey: .stock)
        image = try data.decodeIfPresent(PartImage.self, forKey: .image)
    }
}
struct PartImage: Codable, Equatable {
    var originalPath: String
    var thumbnailPath: String
    var previewPath: String? = nil
    var paths: [String] { [originalPath, thumbnailPath] + (previewPath.map { [$0] } ?? []) }
}
struct Allocation: Identifiable, Codable, Equatable {
    var id: String
    var partID: String
    var project: String
    var quantity: Int
    var designators: String
    init(id: String = UUID().uuidString, partID: String, project: String, quantity: Int, designators: String = "") {
        self.id = id; self.partID = partID; self.project = project; self.quantity = quantity; self.designators = designators
    }
    private enum CodingKeys: String, CodingKey { case id, partID, project, quantity, designators }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(String.self, forKey: .id)
        partID = try data.decode(String.self, forKey: .partID)
        project = try data.decode(String.self, forKey: .project)
        quantity = try data.decode(Int.self, forKey: .quantity)
        designators = try data.decodeIfPresent(String.self, forKey: .designators) ?? ""
    }
}
enum InventoryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
