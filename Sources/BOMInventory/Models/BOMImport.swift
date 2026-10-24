import Foundation

struct BOMImportRow: Identifiable {
    let id = UUID()
    var selected = true
    var values: [String]
    var detected: [String: String] = [:]
}
struct BOMImport: Identifiable {
    let id = UUID()
    var filename: String
    var headers: [String]
    var rows: [BOMImportRow]
    var ignoredCustomColumns: Set<Int> = []
    init(text: String, filename: String) throws {
        let records = try CSVReader.read(text)
        guard let first = records.first, !first.isEmpty else { throw InventoryError.message("The CSV is empty.") }
        headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !headers.contains(""), Set(headers.map { $0.lowercased() }).count == headers.count else { throw InventoryError.message("CSV column names must be nonempty and unique.") }
        self.filename = filename
        rows = try records.dropFirst().enumerated().compactMap { index, record in
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return nil }
            guard record.count <= first.count else { throw InventoryError.message("CSV row \(index + 2) has more values than column names.") }
            return BOMImportRow(values: record + Array(repeating: "", count: first.count - record.count))
        }
        guard !rows.isEmpty else { throw InventoryError.message("No parts were found in the CSV.") }
        for name in ["Value", "Tolerance", "Labels"] where !headers.contains(where: { Self.field(for: $0) == name.lowercased() }) {
            headers.append(name)
            for row in rows.indices { rows[row].values.append("") }
        }
        for row in rows.indices { analyze(row: row) }
    }
    mutating func setValue(_ value: String, row: Int, column: Int) {
        rows[row].values[column] = value
        let field = Self.field(for: headers[column])
        if field == "description" || field == "value" { analyze(row: row) }
        else if let field { rows[row].detected.removeValue(forKey: field) }
    }
    private mutating func analyze(row: Int) {
        func column(_ name: String) -> Int? { headers.firstIndex { Self.field(for: $0) == name } }
        let description = column("description").map { rows[row].values[$0] } ?? ""
        let value = column("value").map { rows[row].values[$0] } ?? ""
        // A previously detected value should be recomputed when description changes.
        let hint = rows[row].detected["value"] == value ? "" : value
        let analysis = DescriptionAnalysis.analyze(description, valueHint: hint)
        let detected = ["value": analysis.value, "tolerance": analysis.tolerance, "labels": analysis.label]
        var owned: [String: String] = [:]
        for name in ["value", "tolerance", "labels"] {
            guard let index = column(name) else { continue }
            let current = rows[row].values[index]
            if current.isEmpty || current == rows[row].detected[name] {
                rows[row].values[index] = detected[name] ?? ""
                owned[name] = detected[name] ?? ""
            }
        }
        rows[row].detected = owned
    }
    static func parseLabels(_ text: String) -> [String] {
        var labels: [String] = []
        for token in text.split(separator: ",") {
            let name = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !labels.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { labels.append(name) }
        }
        return labels
    }
    mutating func commitPendingLabels(_ pending: [UUID: String], suggestions: [String]) {
        guard let column = headers.firstIndex(where: { Self.field(for: $0) == "labels" }) else { return }
        for row in rows.indices where rows[row].selected {
            guard let draft = pending[rows[row].id], !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var names = Self.parseLabels(rows[row].values[column])
            for label in Self.parseLabels(draft) {
                let name = suggestions.first { $0.caseInsensitiveCompare(label) == .orderedSame } ?? label
                if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { names.append(name) }
            }
            setValue(names.joined(separator: ", "), row: row, column: column)
        }
    }
    static func field(for header: String) -> String? {
        let key = header.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "lcsc", "lcscpartnumber": return "lcsc"
        case "partnumber", "manufacturepartnumber", "manufacturerpartnumber", "mpn": return "number"
        case "manufacturer", "manufacture": return "manufacturer"
        case "description": return "description"
        case "package", "footprint": return "package"
        case "quantity", "qty", "stock", "onhandstock": return "stock"
        case "value", "tolerance", "storage", "datasheet", "barcode", "labels": return key
        default: return nil
        }
    }
    func selectedParts() throws -> [Part] {
        var result: [Part] = []
        for (index, row) in rows.enumerated() where row.selected {
            var part = Part()
            for (column, header) in headers.enumerated() {
                let raw = row.values[column]
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                switch Self.field(for: header) {
                case "lcsc": part.lcsc = value
                case "number": part.number = value
                case "manufacturer": part.manufacturer = value
                case "description": part.description = value
                case "package": part.package = value
                case "value": part.value = value
                case "tolerance": part.tolerance = value
                case "storage": part.storage = value
                case "datasheet": part.datasheet = value
                case "barcode": if !value.isEmpty { part.barcode = value }
                case "labels": part.labels = Self.parseLabels(value)
                case "stock":
                    guard let count = Int(value.isEmpty ? "0" : value), count >= 0 else { throw InventoryError.message("Row \(index + 2): quantity must be a nonnegative whole number.") }
                    part.stock = count
                default: if !ignoredCustomColumns.contains(column) { part.customFields[header] = raw }
                }
            }
            guard !part.number.isEmpty else { throw InventoryError.message("Row \(index + 2): enter a manufacturer part number.") }
            result.append(part)
        }
        return result
    }
}

enum CSVReader {
    static func read(_ input: String) throws -> [[String]] {
        let text = input.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(text)
        var rows: [[String]] = [], row: [String] = [], value = ""
        var quoted = false, closedQuote = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { value.append("\""); i += 1 }
                    else { quoted = false; closedQuote = true }
                } else { value.append(c) }
            } else if c == "," {
                row.append(value); value = ""; closedQuote = false
            } else if c == "\n" {
                row.append(value); rows.append(row); row = []; value = ""; closedQuote = false
            } else if c == "\"" && value.isEmpty && !closedQuote { quoted = true }
            else {
                guard !closedQuote && c != "\"" else { throw InventoryError.message("Malformed CSV quoting near row \(rows.count + 1).") }
                value.append(c)
            }
            i += 1
        }
        guard !quoted else { throw InventoryError.message("The CSV contains an unfinished quoted value.") }
        if !row.isEmpty || !value.isEmpty || closedQuote { row.append(value); rows.append(row) }
        return rows
    }
}
