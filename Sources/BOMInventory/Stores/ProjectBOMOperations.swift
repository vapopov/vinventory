import Foundation

extension InventoryStore {
    func bomEntries(for project: String) -> [ProjectBOMEntry] { projectBOMEntries.filter { $0.project.caseInsensitiveCompare(project) == .orderedSame } }
    func requestedQuantity(_ entry: ProjectBOMEntry) -> Int {
        guard let allocation = allocations.first(where: { $0.id == entry.allocationID }) else { return entry.item.quantity }
        var budget = allocation.quantity
        for linked in projectBOMEntries where linked.allocationID == allocation.id {
            let used = min(linked.item.quantity, max(0, budget))
            if linked.id == entry.id { return entry.item.quantity - used }
            budget -= used
        }
        return entry.item.quantity
    }
    func planProjectBOM(_ review: ProjectBOMImport, project: String) throws -> ProjectBOMPlan {
        let previous = bomEntries(for: project)
        let projectAllocations = allocations.filter { $0.project.caseInsensitiveCompare(project) == .orderedSame }
        let importedRefs = try review.rows.filter { $0.included }.reduce(into: Set<String>()) { $0.formUnion(try Designators.references(in: $1.item.designators)) }
        let affectedEntries = previous.filter { !((try? Designators.references(in: $0.item.designators)) ?? []).isDisjoint(with: importedRefs) }
        let linkedIDs = Set(affectedEntries.compactMap(\.allocationID))
        var removing: [String] = [], residualAllocations: [Allocation] = []
        for allocation in projectAllocations {
            let refs = (try? Designators.references(in: allocation.designators)) ?? []
            let overlap = refs.intersection(importedRefs)
            guard !overlap.isEmpty || linkedIDs.contains(allocation.id) else { continue }
            removing.append(allocation.id)
            let remaining = refs.subtracting(importedRefs)
            let quantity = max(0, allocation.quantity - overlap.count)
            if !remaining.isEmpty && quantity > 0 {
                var residual = allocation
                residual.quantity = quantity
                residual.designators = remaining.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ", ")
                residualAllocations.append(residual)
            }
        }
        var residualEntries: [ProjectBOMEntry] = []
        for entry in affectedEntries {
            let refs = try Designators.references(in: entry.item.designators)
            let remaining = refs.subtracting(importedRefs)
            let count = max(0, entry.item.quantity - refs.intersection(importedRefs).count)
            if !remaining.isEmpty && count > 0 {
                var residual = entry
                residual.item.designators = remaining.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ", ")
                residual.item.quantity = count
                if let id = residual.allocationID, removing.contains(id), !residualAllocations.contains(where: { $0.id == id }) { residual.allocationID = nil }
                residualEntries.append(residual)
            }
        }
        var budget: [String: Int] = [:]
        for part in parts {
            let released = projectAllocations.filter { $0.partID == part.id && removing.contains($0.id) }.reduce(0) { $0 + $1.quantity }
            let retained = residualAllocations.filter { $0.partID == part.id }.reduce(0) { $0 + $1.quantity }
            budget[part.id] = available(part) + released - retained
        }
        var planned: [ProjectBOMPlannedRow] = []
        for row in review.rows where row.included {
            var count = 0
            if let id = row.selectedPartID {
                guard row.candidates.contains(id), parts.contains(where: { $0.id == id }) else { throw InventoryError.message("A selected match is no longer available. Re-open the BOM import.") }
                count = min(row.item.quantity, max(0, budget[id] ?? 0)); budget[id, default: 0] -= count
            }
            let refs = try Designators.references(in: row.item.designators)
            let oldID = projectAllocations.first { allocation in ((try? Designators.references(in: allocation.designators)) == refs) && !residualAllocations.contains(where: { $0.id == allocation.id }) }?.id
            planned.append(ProjectBOMPlannedRow(review: row, allocated: count, replacedAllocationID: oldID))
        }
        return ProjectBOMPlan(rows: planned, removing: removing, removingEntries: affectedEntries.map(\.id), residualEntries: residualEntries, residualAllocations: residualAllocations)
    }
    func applyProjectBOM(_ review: ProjectBOMImport, projectName: String) throws {
        guard let project = projects.first(where: { $0.name.caseInsensitiveCompare(projectName) == .orderedSame }) else { throw InventoryError.message("Project no longer exists.") }
        let plan = try planProjectBOM(review, project: project.name)
        let previous = bomEntries(for: project.name)
        var entries = plan.residualEntries
        var reservations = plan.residualAllocations
        for row in plan.rows {
            var entry = previous.first { $0.item.key == row.review.item.key } ?? ProjectBOMEntry(project: project.name, item: row.review.item)
            entry.item = row.review.item; entry.partID = row.review.selectedPartID; entry.allocationID = nil
            if let partID = entry.partID, row.allocated > 0 {
                let allocation = Allocation(id: row.replacedAllocationID ?? UUID().uuidString, partID: partID, project: project.name, quantity: row.allocated, designators: entry.item.designators)
                entry.allocationID = allocation.id; reservations.append(allocation)
            }
            entries.append(entry)
        }
        try saveProjectBOMResult(entries: entries, allocations: reservations, removing: plan.removing, removingEntries: plan.removingEntries)
    }
    func requestCandidates(_ entry: ProjectBOMEntry) -> [Part] {
        if let allocation = allocations.first(where: { $0.id == entry.allocationID }) {
            return parts.filter { $0.id == allocation.partID }
        }
        var matches = ProjectBOMMatcher.candidates(for: entry.item, parts: parts)
        if let confirmed = parts.first(where: { $0.id == entry.partID }), !matches.contains(where: { $0.id == confirmed.id }) {
            matches.insert(confirmed, at: 0)
        }
        return matches
    }
    /// Apply only explicitly checked request matches, retaining existing reservations.
    @discardableResult
    func syncRequests(project: String, matches: [String: String]) throws -> Int {
        guard projects.contains(where: { $0.name.caseInsensitiveCompare(project) == .orderedSame }) else {
            throw InventoryError.message("Project no longer exists.")
        }
        var budget = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, max(0, available($0))) })
        var changedEntries: [ProjectBOMEntry] = []
        var changedAllocations: [String: Allocation] = [:]
        var total = 0
        for original in bomEntries(for: project) {
            let needed = requestedQuantity(original)
            guard needed > 0 else { continue }
            let linked = allocations.first { $0.id == original.allocationID }
            guard let partID = matches[original.id] else { continue }
            guard let part = requestCandidates(original).first(where: { $0.id == partID }) else {
                throw InventoryError.message("A selected match changed. Cancel sync and review the requests again.")
            }
            let count = min(needed, budget[part.id] ?? 0)
            guard count > 0 else { continue }
            var entry = original
            var allocation = linked.flatMap { changedAllocations[$0.id] ?? $0 }
                ?? Allocation(partID: part.id, project: original.project, quantity: 0, designators: original.item.designators)
            allocation.quantity += count
            entry.partID = part.id
            entry.allocationID = allocation.id
            changedEntries.append(entry)
            changedAllocations[allocation.id] = allocation
            budget[part.id, default: 0] -= count
            total += count
        }
        if total > 0 {
            try saveProjectBOMResult(entries: changedEntries, allocations: Array(changedAllocations.values), removing: [], removingEntries: [])
        }
        return total
    }
    func saveRequest(project: String, existing: ProjectBOMEntry?, item: ProjectBOMItem) throws {
        guard item.quantity > 0, !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InventoryError.message("Enter a value or part number and a positive whole-number quantity.")
        }
        var entry = existing ?? ProjectBOMEntry(project: project, item: item)
        let allocated = existing.map { $0.item.quantity - requestedQuantity($0) } ?? 0
        entry.item = item
        entry.item.quantity += allocated
        try saveProjectBOMResult(entries: [entry], allocations: [], removing: [], removingEntries: [])
    }
    func deleteRequest(_ entry: ProjectBOMEntry) throws {
        let allocated = entry.item.quantity - requestedQuantity(entry)
        if allocated > 0 {
            var retained = entry
            retained.item.quantity = allocated
            try saveProjectBOMResult(entries: [retained], allocations: [], removing: [], removingEntries: [])
        } else {
            try saveProjectBOMResult(entries: [], allocations: [], removing: [], removingEntries: [entry.id])
        }
    }
    func requestedCSV(project: String) -> String {
        func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = [["Designator", "Footprint", "Quantity", "Value", "LCSC Part #"].map(escape).joined(separator: ",")]
        for entry in bomEntries(for: project) where requestedQuantity(entry) > 0 {
            let lcsc = entry.item.lcsc.isEmpty ? (parts.first { $0.id == entry.partID }?.lcsc ?? "") : entry.item.lcsc
            lines.append([entry.item.designators, entry.item.package, String(requestedQuantity(entry)), entry.item.value, lcsc].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
