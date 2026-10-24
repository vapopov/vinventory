import Foundation

/// Counts unique component references, including inclusive ranges such as C16-C20.
enum Designators {
    static func quantity(in text: String) throws -> Int? {
        let result = try references(in: text)
        return result.isEmpty ? nil : result.count
    }
    static func references(in text: String) throws -> Set<String> {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var references = Set<String>()
        let pattern = #"^([A-Za-z]+)([0-9]+)(?:\s*-\s*([A-Za-z]+)?([0-9]+))?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        for token in text.split(separator: ",", omittingEmptySubsequences: false) {
            let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(value.startIndex..., in: value)
            guard let match = regex.firstMatch(in: value, range: range), match.range == range else {
                throw InventoryError.message("Use references such as C1, R1, R2 or C16-C20.")
            }
            func group(_ index: Int) -> String? { Range(match.range(at: index), in: value).map { String(value[$0]) } }
            guard let prefix = group(1)?.uppercased(), let first = group(2).flatMap(Int.init) else { throw InventoryError.message("Invalid designator number.") }
            let last = group(4).flatMap(Int.init) ?? first
            guard group(4) == nil || Int(group(4)!) != nil,
                  group(3) == nil || group(3)?.uppercased() == prefix,
                  last >= first, last - first < 100_000 else { throw InventoryError.message("Use an ascending range with the same prefix, such as C16-C20.") }
            for number in first...last { references.insert("\(prefix)\(number)") }
        }
        return references
    }
}
