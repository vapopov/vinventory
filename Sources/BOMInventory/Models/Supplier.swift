import Foundation

enum Supplier {
    static let suggestions = ["LCSC", "DigiKey", "Mouser", "Newark"]
    static func searchURL(spn: String, supplier: String) -> URL? {
        let number = spn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return nil }
        let base: String
        let parameter: String
        switch canonical(supplier) {
        case "LCSC": base = "https://www.lcsc.com/search"; parameter = "q"
        case "DigiKey": base = "https://www.digikey.com/en/products/result"; parameter = "keywords"
        case "Mouser": base = "https://www.mouser.com/c/"; parameter = "q"
        case "Newark": base = "https://www.newark.com/search"; parameter = "st"
        default: return nil
        }
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: parameter, value: number)]
        return components?.url
    }
    static func canonical(_ name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return suggestions.first { $0.lowercased() == key } ?? name
    }
    static func key(_ spn: String, _ supplier: String) -> String {
        let number = spn.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let supplier = canonical(supplier).lowercased()
        return number.isEmpty || supplier.isEmpty ? "" : supplier + "\u{1F}" + number
    }
    static func matches(_ lhs: String, _ lhsSupplier: String, _ rhs: String, _ rhsSupplier: String) -> Bool {
        let left = key(lhs, lhsSupplier)
        return !left.isEmpty && left == key(rhs, rhsSupplier)
    }
    static func validate(spn: String, supplier: String) throws {
        if !spn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && canonical(supplier).isEmpty {
            throw InventoryError.message("Select or enter a supplier for the supplier part number (SPN).")
        }
    }
    static func headerSupplier(_ header: String) -> String? {
        let key = header.lowercased().filter { $0.isLetter || $0.isNumber }
        return suggestions.first { supplier in
            let name = supplier.lowercased()
            return [name, name + "part", name + "partnumber", name + "partno"].contains(key)
        }
    }
}
