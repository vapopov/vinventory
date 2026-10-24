import Foundation
import CSQLite
protocol InventoryRepository {
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
    func delete(_ part: Part) throws
    func save(_ allocation: Allocation) throws
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
        try pruneUnusedSuggestions()
        try execute("PRAGMA user_version = 4")
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
        for label in try loadLabels() where !assignedLabels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
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
    func loadParts() throws -> [Part] { try load("parts") }
    func loadAllocations() throws -> [Allocation] { try load("allocations") }
    func save(_ part: Part) throws { try execute("INSERT INTO parts VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET barcode=excluded.barcode,payload=excluded.payload", values: [part.id, part.barcode, try json(part)]) }
    func delete(_ part: Part) throws { try execute("DELETE FROM parts WHERE id=?", values: [part.id]) }
    func save(_ allocation: Allocation) throws { try execute("INSERT INTO allocations VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", values: [allocation.id, allocation.partID, try json(allocation)]) }
    func delete(_ allocation: Allocation) throws { try execute("DELETE FROM allocations WHERE id=?", values: [allocation.id]) }
}
