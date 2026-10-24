import Foundation
import CSQLite
protocol InventoryRepository {
    func saveCatalog(kind: CatalogKind, originalName: String?, name: String, description: String) throws
    func deleteCatalog(kind: CatalogKind, name: String) throws
    func loadProjectBOMEntries() throws -> [ProjectBOMEntry]
    func saveProjectBOM(entries: [ProjectBOMEntry], allocations: [Allocation], removing: [String], removingEntries: [String]) throws
    func loadProjects() throws -> [Project]
    func saveProjectDescription(name: String, description: String) throws
    func loadStorageDescriptions() throws -> [String: String]
    func saveStorageDescription(name: String, description: String) throws
    func pruneUnusedSuggestions() throws
    func loadSuggestions(for field: RecentField) throws -> [String]
    func registerSuggestion(_ name: String, for field: RecentField) throws
    func loadLabels() throws -> [String]
    func registerLabel(_ name: String) throws
    func loadParts() throws -> [Part]
    func loadAllocations() throws -> [Allocation]
    func save(_ part: Part) throws
    func saveImportedParts(_ parts: [Part]) throws
    func delete(_ part: Part) throws
    func save(_ allocation: Allocation) throws
    func saveMergedAllocation(_ allocation: Allocation, removing duplicates: [Allocation]) throws
    func saveAllocations(_ allocations: [Allocation]) throws
    func delete(_ allocation: Allocation) throws
}
final class SQLiteRepository: InventoryRepository {
    private var db: OpaquePointer?
    init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw InventoryError.message("Cannot open inventory database.") }
        try execute("PRAGMA foreign_keys = ON")
        try execute("CREATE TABLE IF NOT EXISTS parts (id TEXT PRIMARY KEY, barcode TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS allocations (id TEXT PRIMARY KEY, part_id TEXT NOT NULL REFERENCES parts(id) ON DELETE CASCADE, payload TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS labels (name TEXT PRIMARY KEY COLLATE NOCASE, last_used INTEGER NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS field_values (field TEXT NOT NULL, name TEXT NOT NULL COLLATE NOCASE, last_used INTEGER NOT NULL, PRIMARY KEY(field, name))")
        try execute("CREATE TABLE IF NOT EXISTS storage_descriptions (name TEXT PRIMARY KEY COLLATE NOCASE, description TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS projects (name TEXT PRIMARY KEY COLLATE NOCASE, description TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS project_bom_entries (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        for allocation in try loadAllocations() { try ensureProject(allocation.project) }
        // Older payloads decode their Type into labels; seed the persistent catalog once.
        for part in try loadParts() {
            for field in RecentField.allCases {
                let name = field.value(in: part).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    try execute("INSERT OR IGNORE INTO field_values VALUES (?, ?, 0)", values: [field.rawValue, name])
                }
            }
            for label in part.labels {
                try execute("INSERT OR IGNORE INTO labels VALUES (?, 0)", values: [label])
            }
        }
        for part in try loadParts() where !part.storage.isEmpty {
            try execute("INSERT OR IGNORE INTO storage_descriptions VALUES (?, '')", values: [part.storage])
        }
        for label in DescriptionAnalysis.builtInLabels { try execute("INSERT OR IGNORE INTO labels VALUES (?, 0)", values: [label]) }
        try pruneUnusedSuggestions()
        try execute("PRAGMA user_version = 8")
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String, values: [String] = []) throws {
        let statement = try prepare(sql, values: values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    private func failure() -> Error { InventoryError.message(String(cString: sqlite3_errmsg(db))) }
    private func prepare(_ sql: String, values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        return statement
    }
    private func load<T: Decodable>(_ table: String) throws -> [T] {
        let statement = try prepare("SELECT payload FROM \(table) ORDER BY rowid", values: [])
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw failure() }
            results.append(try JSONDecoder().decode(T.self, from: Data(String(cString: text).utf8)))
        }
        return results
    }
    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private func ensureProject(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InventoryError.message("A project name is required.") }
        try execute("INSERT OR IGNORE INTO projects VALUES (?, '')", values: [trimmed])
    }
    func loadProjects() throws -> [Project] {
        let statement = try prepare("SELECT name, description FROM projects ORDER BY name COLLATE NOCASE", values: [])
        defer { sqlite3_finalize(statement) }
        var projects: [Project] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return projects }
            guard status == SQLITE_ROW, let name = sqlite3_column_text(statement, 0), let description = sqlite3_column_text(statement, 1) else { throw failure() }
            projects.append(Project(name: String(cString: name), description: String(cString: description)))
        }
    }
    func saveProjectDescription(name: String, description: String) throws {
        try execute("UPDATE projects SET description=? WHERE name=?", values: [description, name])
    }
    func loadStorageDescriptions() throws -> [String: String] {
        let statement = try prepare("SELECT name, description FROM storage_descriptions", values: [])
        defer { sqlite3_finalize(statement) }
        var descriptions: [String: String] = [:]
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return descriptions }
            guard status == SQLITE_ROW, let name = sqlite3_column_text(statement, 0), let description = sqlite3_column_text(statement, 1) else { throw failure() }
            descriptions[String(cString: name)] = String(cString: description)
        }
    }
    func saveStorageDescription(name: String, description: String) throws {
        try execute("INSERT INTO storage_descriptions VALUES (?,?) ON CONFLICT(name) DO UPDATE SET description=excluded.description", values: [name, description])
    }
    /// Keep recency for assigned values while discarding orphaned catalog entries,
    /// including entries left behind by earlier app versions or cancelled editors.
    func pruneUnusedSuggestions() throws {
        let parts = try loadParts()
        let assignedLabels = parts.flatMap(\.labels)
        for label in try loadLabels() where !DescriptionAnalysis.builtInLabels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) && !assignedLabels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            try execute("DELETE FROM labels WHERE name=?", values: [label])
        }
        for field in RecentField.allCases {
            let assigned = parts.map { field.value(in: $0) }
            for value in try loadSuggestions(for: field) where !assigned.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                try execute("DELETE FROM field_values WHERE field=? AND name=?", values: [field.rawValue, value])
            }
        }
    }
    func loadSuggestions(for field: RecentField) throws -> [String] {
        let statement = try prepare("SELECT name FROM field_values WHERE field=? ORDER BY last_used DESC, name COLLATE NOCASE", values: [field.rawValue])
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return values }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw failure() }
            values.append(String(cString: text))
        }
    }
    func registerSuggestion(_ name: String, for field: RecentField) throws {
        try execute("INSERT INTO field_values(field,name,last_used) VALUES (?, ?, (SELECT COALESCE(MAX(last_used),0)+1 FROM field_values)) ON CONFLICT(field,name) DO UPDATE SET last_used=excluded.last_used", values: [field.rawValue, name])
    }
    func loadLabels() throws -> [String] {
        let statement = try prepare("SELECT name FROM labels ORDER BY last_used DESC, name COLLATE NOCASE", values: [])
        defer { sqlite3_finalize(statement) }
        var labels: [String] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return labels }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw failure() }
            labels.append(String(cString: text))
        }
    }
    func registerLabel(_ name: String) throws {
        try execute("INSERT INTO labels(name,last_used) VALUES (?, (SELECT COALESCE(MAX(last_used),0)+1 FROM labels)) ON CONFLICT(name) DO UPDATE SET last_used=excluded.last_used", values: [name])
    }
    func loadProjectBOMEntries() throws -> [ProjectBOMEntry] { try load("project_bom_entries") }
    func saveProjectBOM(entries: [ProjectBOMEntry], allocations: [Allocation], removing: [String], removingEntries: [String]) throws {
        try transaction {
            for id in removingEntries { try execute("DELETE FROM project_bom_entries WHERE id=?", values: [id]) }
            for id in removing { try execute("DELETE FROM allocations WHERE id=?", values: [id]) }
            for allocation in allocations { try writeAllocation(allocation) }
            for entry in entries { try execute("INSERT INTO project_bom_entries VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [entry.id, try json(entry)]) }
        }
    }
    func loadParts() throws -> [Part] { try load("parts") }
    func loadAllocations() throws -> [Allocation] { try load("allocations") }
    func save(_ part: Part) throws {
        if !part.storage.isEmpty { try execute("INSERT OR IGNORE INTO storage_descriptions VALUES (?, '')", values: [part.storage]) }
        try execute("INSERT INTO parts VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET barcode=excluded.barcode,payload=excluded.payload", values: [part.id, part.barcode, try json(part)]) }
    func saveImportedParts(_ parts: [Part]) throws {
        try transaction {
            for part in parts {
                try save(part)
                for field in RecentField.allCases {
                    let value = field.value(in: part)
                    if !value.isEmpty { try registerSuggestion(value, for: field) }
                }
                for label in part.labels { try registerLabel(label) }
            }
        }
    }
    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func saveCatalog(kind: CatalogKind, originalName: String?, name: String, description: String) throws {
        try transaction {
            let table = kind == .project ? "projects" : "storage_descriptions"
            if let originalName {
                try execute("UPDATE \(table) SET name=?, description=? WHERE name=?", values: [name, description, originalName])
                if kind == .project {
                    for var entry in try loadProjectBOMEntries() where entry.project.caseInsensitiveCompare(originalName) == .orderedSame {
                        entry.project = name
                        try execute("UPDATE project_bom_entries SET payload=? WHERE id=?", values: [try json(entry), entry.id])
                    }
                    for var allocation in try loadAllocations() where allocation.project.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(originalName) == .orderedSame {
                        allocation.project = name
                        try execute("UPDATE allocations SET payload=? WHERE id=?", values: [try json(allocation), allocation.id])
                    }
                } else {
                    for var part in try loadParts() where part.storage.caseInsensitiveCompare(originalName) == .orderedSame {
                        part.storage = name
                        try save(part)
                    }
                    try execute("DELETE FROM field_values WHERE field='storage' AND name=?", values: [originalName])
                }
            } else { try execute("INSERT INTO \(table) VALUES (?, ?)", values: [name, description]) }
        }
    }
    func deleteCatalog(kind: CatalogKind, name: String) throws {
        try transaction {
            if kind == .project {
                for entry in try loadProjectBOMEntries() where entry.project.caseInsensitiveCompare(name) == .orderedSame { try execute("DELETE FROM project_bom_entries WHERE id=?", values: [entry.id]) }
                for allocation in try loadAllocations() where allocation.project.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame {
                    try delete(allocation)
                }
                try execute("DELETE FROM projects WHERE name=?", values: [name])
            } else {
                for var part in try loadParts() where part.storage.caseInsensitiveCompare(name) == .orderedSame {
                    part.storage = ""
                    try save(part)
                }
                try execute("DELETE FROM storage_descriptions WHERE name=?", values: [name])
                try execute("DELETE FROM field_values WHERE field='storage' AND name=?", values: [name])
            }
        }
    }
    func delete(_ part: Part) throws { try execute("DELETE FROM parts WHERE id=?", values: [part.id]) }
    func save(_ allocation: Allocation) throws {
        try saveMergedAllocation(allocation, removing: [])
    }
    func saveMergedAllocation(_ allocation: Allocation, removing duplicates: [Allocation]) throws {
        try transaction {
            try writeAllocation(allocation)
            let mergedIDs = Set(duplicates.map(\.id))
            for var entry in try loadProjectBOMEntries() where entry.allocationID.map(mergedIDs.contains) == true {
                entry.allocationID = allocation.id
                try execute("UPDATE project_bom_entries SET payload=? WHERE id=?", values: [try json(entry), entry.id])
            }
            for duplicate in duplicates where duplicate.id != allocation.id { try delete(duplicate) }
        }
    }
    func saveAllocations(_ allocations: [Allocation]) throws {
        try transaction { for allocation in allocations { try writeAllocation(allocation) } }
    }
    private func writeAllocation(_ allocation: Allocation) throws {
        try ensureProject(allocation.project)
        try execute("INSERT INTO allocations VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET part_id=excluded.part_id,payload=excluded.payload", values: [allocation.id, allocation.partID, try json(allocation)])
    }
    func delete(_ allocation: Allocation) throws { try execute("DELETE FROM allocations WHERE id=?", values: [allocation.id]) }
}
