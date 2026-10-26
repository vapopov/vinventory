import Foundation
import CoreFoundation

struct APIResponse {
    var status: Int
    var data: Data
    static func json(_ value: Any, status: Int = 200) throws -> APIResponse {
        APIResponse(status: status, data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
}

@MainActor struct InventoryAPIRouter {
    var store: InventoryStore
    func handle(method: String, target: String, body: Data) -> APIResponse {
        do { return try route(method: method, target: target, body: body) }
        catch let error as APIError { return (try? .json(["error": error.message], status: error.status)) ?? APIResponse(status: 500, data: Data()) }
        catch { return (try? .json(["error": error.localizedDescription], status: 400)) ?? APIResponse(status: 500, data: Data()) }
    }
    private func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private func route(method: String, target: String, body: Data) throws -> APIResponse {
        guard let url = URLComponents(string: target), target.hasPrefix("/") else { throw APIError(400, "Invalid request target.") }
        let path = url.percentEncodedPath.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if path == ["health"], method == "GET" { return try .json(["status": "ok"]) }
        guard path.first == "v1", path.count >= 2 else { throw APIError(404, "Endpoint not found.") }
        func input() throws -> [String: Any] {
            guard let result = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw APIError(400, "Expected a JSON object.") }
            return result
        }
        func string(_ data: [String: Any], _ key: String, default fallback: String = "") throws -> String {
            guard let value = data[key] else { return fallback }
            guard let text = value as? String else { throw APIError(400, "\(key) must be a string.") }; return text
        }
        if path[1] == "parts" {
            if path.count == 2 {
                if method == "GET" {
                    let query = url.queryItems?.first { $0.name == "q" }?.value ?? ""
                    return try .json(object(store.search(query)))
                }
                if method == "POST" {
                    let data = try input()
                    var part = try mergePart(Part(), changes: data)
                    guard data["number"] != nil else { throw APIError(400, "number is required.") }
                    try store.save(part, recordFieldUse: true)
                    part = store.parts.first { $0.id == part.id } ?? part
                    return try .json(object(part), status: 201)
                }
            } else if path.count == 3 {
                guard let part = store.parts.first(where: { $0.id == path[2] }) else { throw APIError(404, "Part not found.") }
                if method == "GET" { return try .json(object(part)) }
                if method == "PATCH" {
                    let updated = try mergePart(part, changes: input())
                    try store.save(updated, recordFieldUse: true)
                    return try .json(object(store.parts.first { $0.id == part.id } ?? updated))
                }
                if method == "DELETE" { try store.delete(part); return try .json(["deleted": part.id]) }
            }
        }
        if path[1] == "projects" {
            if path.count == 2 {
                if method == "GET" { return try .json(store.projects.map { ["name": $0.name, "description": $0.description] }) }
                if method == "POST" {
                    let data = try input()
                    let name = try string(data, "name")
                    _ = try store.saveCatalog(kind: .project, originalName: nil, name: name, description: string(data, "description"))
                    return try .json(["name": name.trimmingCharacters(in: .whitespacesAndNewlines)], status: 201)
                }
            }
            guard path.count >= 3, let project = store.projects.first(where: { $0.name.caseInsensitiveCompare(path[2]) == .orderedSame }) else { throw APIError(404, "Project not found.") }
            if path.count == 3 {
                if method == "GET" { return try .json(["name": project.name, "description": project.description]) }
                if method == "PATCH" {
                    let data = try input()
                    let name = try store.saveCatalog(kind: .project, originalName: project.name, name: string(data, "name", default: project.name), description: string(data, "description", default: project.description))
                    return try .json(["name": name])
                }
                if method == "DELETE" { try store.deleteCatalog(kind: .project, name: project.name); return try .json(["deleted": project.name]) }
            }
            if path.count >= 4, path[3] == "allocations" {
                if path.count == 4 {
                    if method == "GET" { return try .json(object(store.allocations.filter(project.contains))) }
                    if method == "POST" {
                        let data = try input()
                        let partID = try string(data, "partID")
                        guard let part = store.parts.first(where: { $0.id == partID }) else { throw APIError(404, "Part not found.") }
                        let quantity = try integer(data, "quantity")
                        try store.allocate(part, project: project.name, quantity: quantity, designators: string(data, "designators"))
                        return try .json(object(store.allocations.filter { project.contains($0) && $0.partID == partID }), status: 201)
                    }
                } else if path.count == 5 {
                    guard let allocation = store.allocations.first(where: { $0.id == path[4] && project.contains($0) }) else { throw APIError(404, "Allocation not found.") }
                    if method == "PATCH" {
                        let data = try input()
                        try store.updateAllocation(allocationID: allocation.id, quantity: data["quantity"] == nil ? nil : integer(data, "quantity"), designators: data["designators"] == nil ? nil : string(data, "designators"))
                        return try .json(object(store.allocations.first { $0.id == allocation.id }!))
                    }
                    if method == "DELETE" { try store.release(allocation); return try .json(["released": allocation.id]) }
                }
            }
            if path.count >= 4, path[3] == "requested" {
                if path.count == 4, method == "GET" {
                    return try .json(try store.bomEntries(for: project.name).filter { store.requestedQuantity($0) > 0 }.map { entry -> [String: Any] in
                        var data = try object(entry) as! [String: Any]
                        data["requestedQuantity"] = store.requestedQuantity(entry)
                        return data
                    })
                }
                var existing: ProjectBOMEntry?
                if path.count == 5 {
                    existing = store.bomEntries(for: project.name).first { $0.id == path[4] && store.requestedQuantity($0) > 0 }
                    guard existing != nil else { throw APIError(404, "Requested part not found.") }
                }
                if path.count == 5, method == "DELETE", let existing { try store.deleteRequest(existing); return try .json(["deleted": existing.id]) }
                if (path.count == 4 && method == "POST") || (path.count == 5 && method == "PATCH") {
                    let data = try input()
                    let current = existing?.item
                    let item = ProjectBOMItem(designators: try string(data, "designators", default: current?.designators ?? ""), package: try string(data, "package", default: current?.package ?? ""), quantity: try data["quantity"] == nil ? (existing.map { store.requestedQuantity($0) } ?? 1) : integer(data, "quantity"), value: try string(data, "value", default: current?.value ?? ""), lcsc: try string(data, "lcsc", default: current?.lcsc ?? ""))
                    let before = Set(store.bomEntries(for: project.name).map(\.id))
                    try store.saveRequest(project: project.name, existing: existing, item: item)
                    let result = store.bomEntries(for: project.name).first { entry in existing != nil ? entry.id == existing!.id : !before.contains(entry.id) }
                    return try .json(object(result!), status: existing == nil ? 201 : 200)
                }
            }
        }
        throw APIError(405, "Method or route not supported.")
    }
    private func integer(_ data: [String: Any], _ key: String) throws -> Int {
        guard let number = data[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue, number.doubleValue > 0, number.doubleValue < Double(Int.max) else { throw APIError(400, "\(key) must be a positive integer.") }
        return number.intValue
    }
    private func mergePart(_ part: Part, changes: [String: Any]) throws -> Part {
        let allowed: Set<String> = ["number", "manufacturer", "lcsc", "description", "package", "value", "tolerance", "stock", "storage", "datasheet", "labels", "customFields", "barcode"]
        guard Set(changes.keys).isSubset(of: allowed) else { throw APIError(400, "Unknown or read-only part field.") }
        var data = try object(part) as! [String: Any]
        for (key, value) in changes { data[key] = value }
        if let stock = changes["stock"] as? NSNumber {
            guard CFGetTypeID(stock) != CFBooleanGetTypeID(), stock.doubleValue >= 0, stock.doubleValue.rounded() == stock.doubleValue else { throw APIError(400, "stock must be a nonnegative integer.") }
        }
        return try JSONDecoder().decode(Part.self, from: JSONSerialization.data(withJSONObject: data))
    }
}
private struct APIError: Error { let status: Int; let message: String; init(_ status: Int, _ message: String) { self.status = status; self.message = message } }
