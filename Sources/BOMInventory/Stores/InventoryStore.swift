import Foundation
import Observation
@MainActor @Observable final class InventoryStore {
    private let repository: InventoryRepository
    private let attachmentStorage: AttachmentStorage?
    var parts: [Part] = []
    var allocations: [Allocation] = []
    var projects: [Project] = []
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
        projects = try repository.loadProjects().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        labels = try repository.loadLabels()
        manufacturers = try repository.loadSuggestions(for: .manufacturer)
        packages = try repository.loadSuggestions(for: .package)
        storageLocations = try repository.loadSuggestions(for: .storage)
        storageDescriptions = try repository.loadStorageDescriptions()
    }
    var locations: [StorageLocation] {
        var result = storageLocations.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            StorageLocation(name: name, description: storageDescriptions.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? "")
        }
        if parts.contains(where: { $0.storage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            result.insert(StorageLocation(name: nil, description: "Parts without an assigned storage location"), at: 0)
        }
        return result
    }
    func saveStorageDescription(name: String, description: String) throws {
        guard let canonical = storageLocations.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw InventoryError.message("This storage location is no longer assigned to any parts.")
        }
        try repository.saveStorageDescription(name: canonical, description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        storageDescriptions = try repository.loadStorageDescriptions()
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
        part.tolerance = part.tolerance.trimmingCharacters(in: .whitespacesAndNewlines)
        part.manufacturer = canonical(part.manufacturer, in: manufacturers)
        part.package = canonical(part.package, in: packages)
        part.storage = canonical(part.storage, in: storageLocations)
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
        try repository.save(Allocation(partID: current.id, project: canonical, quantity: quantity, designators: designators.trimmingCharacters(in: .whitespacesAndNewlines)))
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
            let fields = [part.number, part.manufacturer, part.description, part.package, part.value, part.tolerance, part.labels.joined(separator: " "), part.barcode].joined(separator: " ").lowercased()
            return tokens.allSatisfy { fields.contains($0) }
        }.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    }
}
