import Foundation
import Observation
@MainActor @Observable final class InventoryStore {
    private let repository: InventoryRepository
    private let attachmentStorage: AttachmentStorage?
    var parts: [Part] = []
    var allocations: [Allocation] = []
    var labels: [String] = []
    var manufacturers: [String] = []
    var packages: [String] = []
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
        labels = try repository.loadLabels()
        manufacturers = try repository.loadSuggestions(for: .manufacturer)
        packages = try repository.loadSuggestions(for: .package)
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
    func allocate(_ part: Part, project: String, quantity: Int) throws {
        guard !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, quantity > 0, quantity <= available(part) else { throw InventoryError.message("Enter a project and a positive quantity within available stock.") }
        try repository.save(Allocation(partID: part.id, project: project, quantity: quantity)); try reload()
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
