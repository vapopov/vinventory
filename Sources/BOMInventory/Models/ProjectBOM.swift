import Foundation

struct ProjectBOMItem: Codable, Equatable {
    var designators: String
    var package: String
    var quantity: Int
    var value: String
    var lcsc: String
    var key: String { (try? Designators.references(in: designators).sorted().joined(separator: ",")) ?? designators.uppercased() }
}
struct ProjectBOMEntry: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var project: String
    var item: ProjectBOMItem
    var partID: String?
    var allocationID: String?
}
struct ProjectBOMReviewRow: Identifiable {
    var item: ProjectBOMItem
    var candidates: [String]
    var selectedPartID: String?
    var included = true
    var id: String { item.key }
}
struct ProjectBOMImport: Identifiable {
    let id = UUID()
    var filename: String
    var rows: [ProjectBOMReviewRow]
    init(text: String, filename: String, parts: [Part], previous: [ProjectBOMEntry] = []) throws {
        let csv = try CSVReader.read(text)
        guard let headers = csv.first else { throw InventoryError.message("The BOM is empty.") }
        func column(_ names: [String]) -> Int? { headers.firstIndex { names.contains($0.lowercased().filter { $0.isLetter || $0.isNumber }) } }
        guard let refs = column(["designator", "designators", "reference", "references"]), let val = column(["value", "partnumber"]), let qty = column(["quantity", "qty"]), let pkg = column(["footprint", "package"]) else {
            throw InventoryError.message("Project BOM needs Designator, Footprint, Quantity, and Value columns.")
        }
        let lcsc = column(["lcscpart", "lcscpartnumber", "lcsc"])
        var rows: [ProjectBOMReviewRow] = [], seen = Set<String>()
        for (index, cells) in csv.dropFirst().enumerated() where !cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            func cell(_ column: Int) -> String { cells.indices.contains(column) ? cells[column].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            guard let count = Int(cell(qty)), count > 0, !cell(val).isEmpty else { throw InventoryError.message("BOM row \(index + 2) needs a value and positive whole-number quantity.") }
            let references = try Designators.references(in: cell(refs))
            guard !references.isEmpty, seen.isDisjoint(with: references) else { throw InventoryError.message("BOM row \(index + 2) has missing or repeated designators.") }
            seen.formUnion(references)
            let item = ProjectBOMItem(designators: cell(refs), package: cell(pkg), quantity: count, value: cell(val), lcsc: lcsc.map(cell) ?? "")
            let candidates = ProjectBOMMatcher.candidates(for: item, parts: parts).map(\.id)
            let old = previous.first { $0.item.key == item.key }?.partID
            rows.append(ProjectBOMReviewRow(item: item, candidates: candidates, selectedPartID: old.flatMap { candidates.contains($0) ? $0 : nil }))
        }
        guard !rows.isEmpty else { throw InventoryError.message("No BOM rows found.") }
        self.filename = filename; self.rows = rows
    }
}
struct ProjectBOMPlannedRow {
    var review: ProjectBOMReviewRow
    var allocated: Int
    var requested: Int { review.item.quantity - allocated }
    var replacedAllocationID: String?
}
struct ProjectBOMPlan {
    var rows: [ProjectBOMPlannedRow]
    var removing: [String]
    var removingEntries: [String]
    var residualEntries: [ProjectBOMEntry]
    var residualAllocations: [Allocation]
}

enum ProjectBOMMatcher {
    static func normalized(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func candidates(for item: ProjectBOMItem, parts: [Part]) -> [Part] {
        let exact = parts.filter { normalized($0.number) == normalized(item.value) || (!item.lcsc.isEmpty && normalized($0.lcsc) == normalized(item.lcsc)) }
        if !exact.isEmpty { return exact.sorted { $0.number < $1.number } }
        let kind = componentKind(item)
        if let value = magnitude(item.value, kind: kind), !item.package.isEmpty {
            return parts.filter { part in
                let text = part.value.isEmpty ? DescriptionAnalysis.analyze(part.description).value : part.value
                guard let candidate = magnitude(text, kind: kind) else { return false }
                return package(part.package) == package(item.package) && abs(candidate - value) <= max(abs(value) * 1e-9, 1e-18)
            }.sorted { $0.number < $1.number }
        }
        // Supplier MPNs often add packing suffixes. Offer these for explicit review only.
        let key = normalized(item.value)
        return key.count >= 5 ? parts.filter { normalized($0.number).hasPrefix(key) }.sorted { $0.number < $1.number } : []
    }
    static func componentKind(_ item: ProjectBOMItem) -> String {
        let label = DescriptionAnalysis.analyze(item.value).label
        if !label.isEmpty { return label }
        let prefix = item.designators.uppercased().prefix(while: { $0.isLetter })
        switch prefix { case "R": return "Resistor"; case "C": return "Capacitor"; case "L": return "Inductor"; case "Y", "X": return "Crystal"; default: return "" }
    }
    static func magnitude(_ raw: String, kind: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u")
        func groups(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        if kind == "Resistor", let m = groups(#"^(\d+)([RrKkMm])(\d+)(?:(?i:ohms?)|[ΩΩ])?(?![A-Za-z])"#), let value = Double(m[1] + "." + m[3]) {
            return value * scale(m[2])
        }
        let suffix: String
        switch kind {
        case "Resistor": suffix = #"(?:[Rr]|(?i:ohms?)|[ΩΩ])?"#
        case "Capacitor": suffix = "F"
        case "Inductor": suffix = "H"
        case "Crystal", "Oscillator": suffix = "(?i:Hz)"
        default: return nil
        }
        guard let m = groups(#"^(\d+(?:\.\d+)?|\.\d+)\s*([pPnNuUmMkKG]?)\s*(?:"# + suffix + #")(?![A-Za-z])"#), let value = Double(m[1]) else { return nil }
        // A unitless numeric value is meaningful only for resistor BOM notation.
        return value * scale(m[2])
    }
    private static func scale(_ prefix: String) -> Double {
        switch prefix { case "p", "P": return 1e-12; case "n", "N": return 1e-9; case "u", "U": return 1e-6; case "m": return 1e-3; case "k", "K": return 1e3; case "M": return 1e6; case "G": return 1e9; default: return 1 }
    }
    static func package(_ raw: String) -> String {
        let text = raw.components(separatedBy: ":").last ?? raw
        if let range = text.range(of: #"(?<!\d)(?:01005|0201|0402|0603|0805|1206|1210|1812|2010|2512|3225)(?!\d)"#, options: .regularExpression) { return String(text[range]) }
        return text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
