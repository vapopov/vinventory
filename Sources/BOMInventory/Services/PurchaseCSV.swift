import Foundation

enum PurchaseCSV {
    /// Project exports use assigned quantities; full-cart exports use total planned quantities.
    static func encode(_ purchases: [PurchaseItem], project: String? = nil) -> String {
        let items = purchases.filter { item in
            guard let project else { return true }
            return item.assignments.contains { $0.project.caseInsensitiveCompare(project) == .orderedSame }
        }.sorted { $0.part.number.localizedStandardCompare($1.part.number) == .orderedAscending }
        let customKeys = Set(items.flatMap { $0.part.customFields.keys }).sorted()
        var rows = [["Part Number", "LCSC", "Manufacturer", "Description", "Package", "Value", "Tolerance", "Quantity", "Projects", "Designators", "Labels", "Datasheet"] + customKeys.map { "Custom: " + $0 }]
        for item in items {
            let part = item.part
            let assignments = item.assignments.filter { assignment in
                project.map { assignment.project.caseInsensitiveCompare($0) == .orderedSame } ?? true
            }
                .sorted { $0.project.localizedStandardCompare($1.project) == .orderedAscending }
            let quantity = project == nil ? part.stock : assignments.reduce(0) { $0 + $1.quantity }
            let designators = assignments.map { assignment in
                project == nil ? "\(assignment.project): \(assignment.designators)" : assignment.designators
            }.joined(separator: "; ")
            rows.append([part.number, part.lcsc, part.manufacturer, part.description, part.package, part.value, part.tolerance,
                         String(quantity), assignments.map(\.project).joined(separator: "; "), designators,
                         part.labels.joined(separator: ", "), part.datasheet] + customKeys.map { part.customFields[$0] ?? "" })
        }
        return rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
