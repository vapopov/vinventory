import Foundation

@MainActor extension InventoryAPIRouter {
    func purchaseObject(_ item: PurchaseItem) throws -> [String: Any] {
        ["id": item.id, "part": try object(item.part), "quantity": item.part.stock, "assignments": try object(item.assignments)]
    }
    private func purchaseInput(_ body: Data) throws -> [String: Any] {
        guard let data = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw APIError(400, "Expected a JSON object.") }
        return data
    }
    func purchaseRoute(method: String, path: [String], body: Data, query: String) throws -> APIResponse {
        if path.count == 3, path[2] == "receive", method == "POST" {
            let input = try purchaseInput(body)
            guard let ids = input["ids"] as? [String] else { throw APIError(400, "ids must be an array of purchase item IDs.") }
            let received = try store.receivePurchases(ids: Set(ids))
            return try .json(["receivedPartIDs": received, "receivedPurchaseIDs": ids])
        }
        if path.count == 2, method == "GET" { return try .json(try store.purchaseSearch(query).map(purchaseObject)) }
        let existing: PurchaseItem?
        if path.count == 3 {
            guard let item = store.purchases.first(where: { $0.id == path[2] }) else { throw APIError(404, "Purchase item not found.") }
            existing = item
            if method == "GET" { return try .json(purchaseObject(item)) }
            if method == "DELETE" { try store.deletePurchase(item); return try .json(["deleted": item.id]) }
        } else { existing = nil }
        if (path.count == 2 && method == "POST") || (path.count == 3 && method == "PATCH") {
            let input = try purchaseInput(body)
            guard Set(input.keys).isSubset(of: ["part", "quantity", "assignments"]) else { throw APIError(400, "Use part, quantity, and assignments fields.") }
            var item = existing ?? PurchaseItem()
            if let value = input["part"] {
                guard let fields = value as? [String: Any], fields["stock"] == nil else { throw APIError(400, "part must be an object; use quantity instead of part.stock.") }
                item.part = try mergePart(item.part, changes: fields)
            }
            if input["quantity"] != nil { item.part.stock = try integer(input, "quantity") }
            if let value = input["assignments"] {
                struct AssignmentInput: Decodable { var project: String; var quantity: Int; var designators: String? }
                let assignments = try JSONDecoder().decode([AssignmentInput].self, from: JSONSerialization.data(withJSONObject: value))
                item.assignments = assignments.map { input in
                    var assignment = existing?.assignments.first { $0.project.caseInsensitiveCompare(input.project) == .orderedSame } ?? PurchaseAssignment(project: input.project, quantity: input.quantity)
                    assignment.quantity = input.quantity; assignment.designators = input.designators ?? ""
                    return assignment
                }
            }
            try store.savePurchase(item)
            return try .json(purchaseObject(store.purchases.first { $0.id == item.id } ?? item), status: existing == nil ? 201 : 200)
        }
        throw APIError(405, "Unsupported purchase route or method.")
    }
    func projectPurchaseRoute(method: String, path: [String], body: Data, project: String) throws -> APIResponse {
        if path.count == 4, method == "GET" {
            let rows = try store.purchases.compactMap { item -> [String: Any]? in
                guard let assignment = item.assignments.first(where: { $0.project.caseInsensitiveCompare(project) == .orderedSame }) else { return nil }
                return ["purchaseID": item.id, "part": try object(item.part), "assignment": try object(assignment)]
            }
            return try .json(rows)
        }
        let input = method == "DELETE" ? [:] : try purchaseInput(body)
        let id = path.count == 5 ? path[4] : input["purchaseID"] as? String ?? ""
        guard let item = store.purchases.first(where: { $0.id == id }) else { throw APIError(404, "Purchase item not found.") }
        let existing = item.assignments.first { $0.project.caseInsensitiveCompare(project) == .orderedSame }
        if path.count == 5, existing == nil { throw APIError(404, "Project purchase assignment not found.") }
        if path.count == 5, method == "DELETE" {
            try store.removePurchaseAssignment(itemID: id, project: project)
            return try .json(["removed": id, "project": project])
        }
        if (path.count == 4 && method == "POST") || (path.count == 5 && method == "PATCH") {
            let quantity = try input["quantity"] == nil ? (existing?.quantity ?? 1) : integer(input, "quantity")
            let designators: String
            if let value = input["designators"] { guard let text = value as? String else { throw APIError(400, "designators must be a string.") }; designators = text }
            else { designators = existing?.designators ?? "" }
            try store.savePurchaseAssignment(itemID: id, project: project, quantity: quantity, designators: designators, inferQuantity: input["designators"] != nil && designators != existing?.designators)
            return try .json(purchaseObject(store.purchases.first { $0.id == id }!), status: existing == nil ? 201 : 200)
        }
        throw APIError(405, "Unsupported project purchase route or method.")
    }
}
