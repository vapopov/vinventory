import Foundation

extension InventoryStore {
    func purchaseSearch(_ query: String) -> [PurchaseItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return purchases.filter { item in
            let p = item.part
            let fields = ([p.number, p.manufacturer, p.lcsc, p.description, p.package, p.value, p.tolerance, p.barcode] + p.labels + item.assignments.map(\.project)).joined(separator: " ").lowercased()
            return words.allSatisfy { fields.contains($0) }
        }.sorted { $0.part.number.localizedStandardCompare($1.part.number) == .orderedAscending }
    }
    func validatePurchase(_ item: PurchaseItem) throws {
        guard !item.part.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.part.stock > 0 else { throw InventoryError.message("Enter a part number and positive purchase quantity.") }
        guard !item.part.barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InventoryError.message("Barcode cannot be empty.") }
        var total = 0
        var assigned = Set<String>()
        for assignment in item.assignments {
            guard projects.contains(where: { $0.name.caseInsensitiveCompare(assignment.project) == .orderedSame }), assignment.quantity > 0,
                  assignment.quantity <= item.part.stock - total, assigned.insert(assignment.project.lowercased()).inserted else {
                throw InventoryError.message("Select an existing project once per item; assigned quantities must be positive and cannot exceed the purchase quantity.")
            }
            _ = try Designators.references(in: assignment.designators)
            total += assignment.quantity
        }
    }
    func savePurchase(_ original: PurchaseItem) throws {
        var item = original
        item.part.number = item.part.number.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in item.assignments.indices {
            if let project = projects.first(where: { $0.name.caseInsensitiveCompare(item.assignments[index].project) == .orderedSame }) { item.assignments[index].project = project.name }
        }
        try validatePurchase(item)
        let previous = purchases.first { $0.id == item.id }?.part
        let prepared = try attachmentStorage?.prepare(item.part)
        item.part = prepared?.part ?? item.part
        do { try repository.savePurchase(item) } catch { prepared?.rollback(); throw error }
        do { try attachmentStorage?.removeReplaced(previous: previous, current: item.part) }
        catch { self.error = "Purchase saved, but old attachments could not be removed: \(error.localizedDescription)" }
        try reload()
    }
    func deletePurchase(_ item: PurchaseItem) throws {
        try repository.deletePurchase(item.id)
        try reload()
        try attachmentStorage?.removePart(item.part.id)
    }
    func savePurchaseAssignment(itemID: String, project: String, quantity: Int, designators: String, inferQuantity: Bool = false) throws {
        guard var item = purchases.first(where: { $0.id == itemID }) else { throw InventoryError.message("Purchase item not found.") }
        let count = inferQuantity ? (try Designators.quantity(in: designators) ?? quantity) : quantity
        if let index = item.assignments.firstIndex(where: { $0.project.caseInsensitiveCompare(project) == .orderedSame }) {
            item.assignments[index].quantity = count; item.assignments[index].designators = designators
        } else { item.assignments.append(PurchaseAssignment(project: project, quantity: count, designators: designators)) }
        try savePurchase(item)
    }
    func removePurchaseAssignment(itemID: String, project: String) throws {
        guard var item = purchases.first(where: { $0.id == itemID }) else { throw InventoryError.message("Purchase item not found.") }
        item.assignments.removeAll { $0.project.caseInsensitiveCompare(project) == .orderedSame }
        try savePurchase(item)
    }
    /// Commit stock, project reservations, and cart removal in one database transaction.
    @discardableResult func receivePurchases(ids: Set<String>) throws -> [String] {
        guard !ids.isEmpty, ids.isSubset(of: Set(purchases.map(\.id))) else { throw InventoryError.message("Select existing purchase items to receive.") }
        var workingParts = parts
        var workingAllocations = allocations
        var entries = projectBOMEntries
        var changedParts = Set<String>(), changedAllocations = Set<String>(), changedEntries = Set<String>()
        var prepared: [PreparedAttachments] = []
        do {
            for item in purchases where ids.contains(item.id) {
                try validatePurchase(item)
                let p = item.part
                let matches = workingParts.indices.filter {
                    workingParts[$0].number.caseInsensitiveCompare(p.number) == .orderedSame ||
                    (!p.lcsc.isEmpty && workingParts[$0].lcsc.caseInsensitiveCompare(p.lcsc) == .orderedSame)
                }
                guard matches.count <= 1 else { throw InventoryError.message("Multiple inventory matches for \(p.number). Resolve duplicates before receiving.") }
                let target: Part
                if let index = matches.first {
                    var existing = workingParts[index]
                    let sum = existing.stock.addingReportingOverflow(p.stock)
                    guard !sum.overflow else { throw InventoryError.message("Stock quantity is too large.") }
                    existing.stock = sum.partialValue
                    workingParts[index] = existing; target = existing
                } else {
                    guard !workingParts.contains(where: { $0.id == p.id || $0.barcode == p.barcode }) else { throw InventoryError.message("Inventory barcode or identifier already exists.") }
                    let attachments = try attachmentStorage?.prepare(p)
                    if let attachments { prepared.append(attachments) }
                    target = attachments?.part ?? p
                    workingParts.append(target)
                }
                changedParts.insert(target.id)
                for assignment in item.assignments {
                    let index = workingAllocations.firstIndex { $0.partID == target.id && $0.project.caseInsensitiveCompare(assignment.project) == .orderedSame }
                    var allocation = index.map { workingAllocations[$0] } ?? Allocation(partID: target.id, project: assignment.project, quantity: 0)
                    let sum = allocation.quantity.addingReportingOverflow(assignment.quantity)
                    guard !sum.overflow else { throw InventoryError.message("Allocation quantity is too large.") }
                    allocation.quantity = sum.partialValue
                    allocation.designators = [allocation.designators, assignment.designators].filter { !$0.isEmpty }.joined(separator: ", ")
                    if let index { workingAllocations[index] = allocation } else { workingAllocations.append(allocation) }
                    changedAllocations.insert(allocation.id)
                    // Link the same reference group to its received reservation, if it was requested.
                    let refs = try Designators.references(in: assignment.designators)
                    if !refs.isEmpty {
                        for i in entries.indices where entries[i].project.caseInsensitiveCompare(assignment.project) == .orderedSame && entries[i].allocationID == nil {
                            if (try? Designators.references(in: entries[i].item.designators)) == refs {
                                entries[i].partID = target.id; entries[i].allocationID = allocation.id; changedEntries.insert(entries[i].id)
                            }
                        }
                    }
                }
            }
            try repository.receivePurchases(parts: workingParts.filter { changedParts.contains($0.id) }, allocations: workingAllocations.filter { changedAllocations.contains($0.id) }, entries: entries.filter { changedEntries.contains($0.id) }, removing: Array(ids))
        } catch { prepared.forEach { $0.rollback() }; throw error }
        try reload()
        // New inventory parts retain their managed attachments; merged rows no longer need the cart files.
        for id in ids where !parts.contains(where: { $0.id == id }) {
            do { try attachmentStorage?.removePart(id) } catch { self.error = "Received stock, but cart attachment cleanup failed: \(error.localizedDescription)" }
        }
        return changedParts.sorted()
    }
}
