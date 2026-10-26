import Foundation
import Observation
@MainActor @Observable final class InventoryStore {
    private let repository: InventoryRepository
    private let attachmentStorage: AttachmentStorage?
    var parts: [Part] = []
    var allocations: [Allocation] = []
    var projects: [Project] = []
    var projectBOMEntries: [ProjectBOMEntry] = []
    var labels: [String] = []
    var manufacturers: [String] = []
    var packages: [String] = []
    var storageLocations: [String] = []
    var storageDescriptions: [String: String] = [:]
    var error: String?
    init(repository: InventoryRepository, attachmentStorage: AttachmentStorage? = nil) {
        self.repository = repository
        self.attachmentStorage = attachmentStorage
        perform { try reload() }
    }
    func perform(_ operation: () throws -> Void) { do { try operation() } catch { self.error = error.localizedDescription } }
    func reload() throws {
        try repository.pruneUnusedSuggestions()
        parts = try repository.loadParts()
        if let attachmentStorage {
            for index in parts.indices {
                let upgraded = try attachmentStorage.ensurePreview(for: parts[index])
                if upgraded != parts[index] { try repository.save(upgraded); parts[index] = upgraded }
            }
        }
        allocations = try repository.loadAllocations()
        projectBOMEntries = try repository.loadProjectBOMEntries()
        projects = try repository.loadProjects().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        labels = try repository.loadLabels()
        manufacturers = try repository.loadSuggestions(for: .manufacturer)
        packages = try repository.loadSuggestions(for: .package)
        storageLocations = try repository.loadSuggestions(for: .storage)
        storageDescriptions = try repository.loadStorageDescriptions()
    }
    var storageSuggestions: [String] {
        storageLocations + storageDescriptions.keys.filter { name in
            !storageLocations.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var locations: [StorageLocation] {
        var result = Array(storageDescriptions.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            StorageLocation(name: name, description: storageDescriptions.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? "")
        }
        result.insert(StorageLocation(name: nil, description: "Parts without an assigned storage location"), at: 0)
        return result
    }
    func saveStorageDescription(name: String, description: String) throws {
        guard let canonical = storageDescriptions.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw InventoryError.message("This storage location is no longer assigned to any parts.")
        }
        try repository.saveStorageDescription(name: canonical, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        storageDescriptions = try repository.loadStorageDescriptions()
    }
    func saveCatalog(kind: CatalogKind, originalName: String?, name: String, description: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.caseInsensitiveCompare("(no storage)") != .orderedSame else { throw InventoryError.message("Enter a name; (no storage) is reserved.") }
        let names = kind == .project ? projects.map(\.name) : Array(storageDescriptions.keys)
        if let originalName, !names.contains(where: { $0.caseInsensitiveCompare(originalName) == .orderedSame }) { throw InventoryError.message("This entry no longer exists.") }
        guard !names.contains(where: { candidate in
            candidate.caseInsensitiveCompare(name) == .orderedSame && (originalName == nil || candidate.caseInsensitiveCompare(originalName!) != .orderedSame)
        }) else { throw InventoryError.message("This name already exists.") }
        try repository.saveCatalog(kind: kind, originalName: originalName, name: name, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        try reload()
        return name
    }
    func deleteCatalog(kind: CatalogKind, name: String) throws {
        try repository.deleteCatalog(kind: kind, name: name)
        try reload()
    }
    // Draft labels stay on the editor's part; only saved assignments enter autocomplete.
    func labelName(for input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InventoryError.message("Enter a label name.") }
        return labels.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }
    func labelSuggestions(for query: String, excluding selected: [String] = []) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(labels.filter { label in
            !selected.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) &&
            (trimmed.isEmpty || label.localizedCaseInsensitiveContains(trimmed))
        }.prefix(10))
    }
    func projectCount(_ part: Part) -> Int {
        Set(allocations.filter { $0.partID == part.id && $0.quantity > 0 }
            .map { $0.project.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }).count
    }
    func allocated(_ part: Part) -> Int { allocations.filter { $0.partID == part.id }.reduce(0) { $0 + $1.quantity } }
    func available(_ part: Part) -> Int { part.stock - allocated(part) }
    func save(_ part: Part, recordFieldUse: Bool = false) throws {
        var part = part
        let previous = parts.first { $0.id == part.id }
        guard !part.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InventoryError.message("Enter a part number.") }
        guard !part.barcode.isEmpty else { throw InventoryError.message("A barcode is required.") }
        guard part.stock >= allocated(part) else { throw InventoryError.message("Stock cannot be less than the allocated quantity.") }
        part.datasheet = part.datasheet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !part.datasheet.isEmpty {
            let url = try DatasheetReference.url(for: part.datasheet)
            if url.isFileURL {
                guard attachmentStorage != nil else { throw InventoryError.message("Local attachment storage is unavailable.") }
                try DatasheetReference.validatePDF(at: url)
            }
        }
        if part.image != nil && attachmentStorage == nil { throw InventoryError.message("Local attachment storage is unavailable.") }
        var canonicalLabels: [String] = []
        for label in part.labels where !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonical = (labels + canonicalLabels).first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
            if !canonicalLabels.contains(canonical) { canonicalLabels.append(canonical) }
        }
        part.labels = canonicalLabels
        part.lcsc = part.lcsc.trimmingCharacters(in: .whitespacesAndNewlines)
        part.tolerance = part.tolerance.trimmingCharacters(in: .whitespacesAndNewlines)
        part.manufacturer = canonical(part.manufacturer, in: manufacturers)
        part.package = canonical(part.package, in: packages)
        part.storage = canonical(part.storage, in: Array(storageDescriptions.keys))
        let prepared = try attachmentStorage?.prepare(part)
        part = prepared?.part ?? part
        do { try repository.save(part) }
        catch { prepared?.rollback(); throw error }
        do { try attachmentStorage?.removeReplaced(previous: previous, current: part) }
        catch { self.error = "Part saved, but old attachments could not be removed: \(error.localizedDescription)" }
        if !part.manufacturer.isEmpty && (recordFieldUse || previous?.manufacturer != part.manufacturer) {
            try repository.registerSuggestion(part.manufacturer, for: .manufacturer)
        }
        if !part.package.isEmpty && (recordFieldUse || previous?.package != part.package) {
            try repository.registerSuggestion(part.package, for: .package)
        }
        if !part.storage.isEmpty && (recordFieldUse || previous?.storage != part.storage) {
            try repository.registerSuggestion(part.storage, for: .storage)
        }
        // Editor saves record label use; stock-only changes preserve recency.
        for label in canonicalLabels where recordFieldUse || !labels.contains(label) { try repository.registerLabel(label) }
        try reload()
    }
    private func canonical(_ input: String, in values: [String]) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return values.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }
    func delete(_ part: Part) throws {
        try repository.delete(part)
        let cleanup = Result { try attachmentStorage?.removePart(part.id) }
        try reload()
        try cleanup.get()
    }
    func allocate(_ part: Part, project: String, quantity: Int, designators: String = "") throws {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = parts.first(where: { $0.id == part.id }), !trimmed.isEmpty, quantity > 0, quantity <= available(current) else {
            throw InventoryError.message("Enter a project and a positive quantity within available stock.")
        }
        let canonical = projects.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }?.name ?? trimmed
        let existing = allocations.filter { $0.partID == current.id && $0.project.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(canonical) == .orderedSame }
        var combined = existing.first ?? Allocation(partID: current.id, project: canonical, quantity: 0)
        combined.project = canonical
        combined.quantity = existing.reduce(quantity) { $0 + $1.quantity }
        combined.designators = (existing.map(\.designators) + [designators])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        try repository.saveMergedAllocation(combined, removing: Array(existing.dropFirst()))
        try reload()
    }
    func importParts(_ imported: [Part]) throws {
        func key(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var working = parts
        var numberIndex: [String: Set<Int>] = [:], lcscIndex: [String: Set<Int>] = [:]
        func register(_ part: Part, at index: Int) {
            if !key(part.number).isEmpty { numberIndex[key(part.number), default: []].insert(index) }
            if !key(part.lcsc).isEmpty { lcscIndex[key(part.lcsc), default: []].insert(index) }
        }
        for (index, part) in working.enumerated() { register(part, at: index) }
        var barcodes = Set(parts.map(\.barcode)), changed = Set<Int>()
        for var part in imported {
            part.number = part.number.trimmingCharacters(in: .whitespacesAndNewlines)
            part.lcsc = part.lcsc.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.number.isEmpty, part.stock >= 0 else { throw InventoryError.message("Every imported part needs a part number and nonnegative stock.") }
            let matches = (numberIndex[key(part.number)] ?? []).union(key(part.lcsc).isEmpty ? [] : (lcscIndex[key(part.lcsc)] ?? []))
            guard matches.count <= 1 else { throw InventoryError.message("\(part.number): part number or LCSC number matches multiple inventory parts. Resolve the conflicting identifiers before importing.") }
            var canonicalLabels: [String] = []
            for label in part.labels {
                let name = canonical(label, in: labels + working.flatMap(\.labels) + canonicalLabels)
                if !name.isEmpty && !canonicalLabels.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { canonicalLabels.append(name) }
            }
            part.labels = canonicalLabels
            if let index = matches.first {
                let (stock, overflow) = working[index].stock.addingReportingOverflow(part.stock)
                guard !overflow else { throw InventoryError.message("Stock quantity is too large for \(part.number).") }
                working[index].stock = stock
                for label in part.labels where !working[index].labels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) { working[index].labels.append(label) }
                if working[index].lcsc.isEmpty { working[index].lcsc = part.lcsc }
                register(part, at: index)
                changed.insert(index)
            } else {
                guard barcodes.insert(part.barcode).inserted else { throw InventoryError.message("Duplicate barcode for \(part.number).") }
                part.manufacturer = canonical(part.manufacturer, in: manufacturers + working.map(\.manufacturer))
                part.package = canonical(part.package, in: packages + working.map(\.package))
                part.storage = canonical(part.storage, in: Array(storageDescriptions.keys) + working.map(\.storage))
                if !part.datasheet.isEmpty {
                    let url = try DatasheetReference.url(for: part.datasheet)
                    guard !url.isFileURL else { throw InventoryError.message("Import datasheets as web links; use the part editor for local PDFs.") }
                }
                let index = working.count
                working.append(part); register(part, at: index); changed.insert(index)
            }
        }
        try repository.saveImportedParts(changed.sorted().map { working[$0] })
        try reload()
    }
    func saveProjectBOMResult(entries: [ProjectBOMEntry], allocations: [Allocation], removing: [String], removingEntries: [String]) throws {
        try repository.saveProjectBOM(entries: entries, allocations: allocations, removing: removing, removingEntries: removingEntries)
        try reload()
    }
    func allocateBulk(projectName: String, drafts: [Allocation]) throws {
        guard let project = projects.first(where: { $0.name.caseInsensitiveCompare(projectName) == .orderedSame }) else { throw InventoryError.message("This project no longer exists.") }
        var seen = Set<String>()
        var additions: [Allocation] = []
        for draft in drafts where draft.quantity != 0 || !draft.designators.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let part = parts.first(where: { $0.id == draft.partID }) else { throw InventoryError.message("A selected part no longer exists.") }
            guard seen.insert(part.id).inserted, !allocations.contains(where: { $0.partID == part.id && project.contains($0) }) else { throw InventoryError.message("\(part.number) is already allocated to this project. Cancel bulk adding and refresh the list.") }
            guard draft.quantity > 0, draft.quantity <= available(part) else { throw InventoryError.message("\(part.number): enter a positive quantity within available stock (\(available(part))).") }
            additions.append(Allocation(partID: part.id, project: project.name, quantity: draft.quantity, designators: draft.designators.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        guard !additions.isEmpty else { return }
        try repository.saveAllocations(additions)
        try reload()
    }
    func saveProjectDescription(name: String, description: String) throws {
        guard let project = projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw InventoryError.message("This project is no longer available.")
        }
        try repository.saveProjectDescription(name: project.name, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        projects = try repository.loadProjects().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func saveDesignators(allocationID: String, value: String) throws {
        try updateAllocation(allocationID: allocationID, designators: value)
    }
    func saveQuantity(allocationID: String, value: String) throws {
        guard let quantity = Int(value) else { throw InventoryError.message("Enter a positive whole-number quantity.") }
        try updateAllocation(allocationID: allocationID, quantity: quantity)
    }
    func updateAllocation(allocationID: String, quantity: Int? = nil, designators: String? = nil) throws {
        guard var allocation = allocations.first(where: { $0.id == allocationID }),
              let part = parts.first(where: { $0.id == allocation.partID }) else {
            throw InventoryError.message("This allocation has already been released.")
        }
        let previousQuantity = allocation.quantity
        if let quantity { allocation.quantity = quantity }
        if let designators {
            let trimmed = designators.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != allocation.designators {
                allocation.designators = trimmed
                if let count = try Designators.quantity(in: trimmed) { allocation.quantity = count }
            }
        }
        guard allocation.quantity > 0, allocation.quantity <= available(part) + previousQuantity else {
            throw InventoryError.message("Enter a positive quantity within available stock (up to \(available(part) + previousQuantity)).")
        }
        try repository.save(allocation)
        try reload()
    }
    func release(_ allocation: Allocation) throws { try repository.delete(allocation); try reload() }
    func search(_ query: String) -> [Part] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        return parts.filter { part in
            let fields = [part.number, part.manufacturer, part.lcsc, part.customFields.map { "\($0.key) \($0.value)" }.joined(separator: " "), part.description, part.package, part.value, part.tolerance, part.labels.joined(separator: " "), part.barcode].joined(separator: " ").lowercased()
            return tokens.allSatisfy { fields.contains($0) }
        }.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    }
}


extension InventoryStore {
    /// Assign whole parts to a location without changing quantities or reservations.
    func assignStorage(_ name: String?, partIDs: Set<String>) throws {
        let destination: String
        if let name {
            guard let location = locations.first(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }), let canonical = location.name else {
                throw InventoryError.message("Storage no longer exists.")
            }
            destination = canonical
        } else { destination = "" }
        guard partIDs.isSubset(of: Set(parts.map(\.id))) else { throw InventoryError.message("A selected part no longer exists. Reopen bulk adding.") }
        let updates = parts.filter { partIDs.contains($0.id) }.map { original in
            var part = original; part.storage = destination; return part
        }
        guard !updates.isEmpty else { return }
        try repository.saveImportedParts(updates)
        try reload()
    }
}
