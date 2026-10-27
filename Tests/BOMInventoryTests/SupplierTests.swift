import XCTest
@testable import BOMInventory

final class SupplierTests: XCTestCase {
    func testSupplierLinksUseCorrectHostAndSearchParameter() throws {
        for (supplier, host, parameter) in [("LCSC", "www.lcsc.com", "q"), ("digi-key", "www.digikey.com", "keywords"), ("Mouser", "www.mouser.com", "q"), ("Newark", "www.newark.com", "st")] {
            let url = try XCTUnwrap(Supplier.searchURL(spn: "C160982 / A&B", supplier: supplier))
            XCTAssertEqual(url.host, host)
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query, [URLQueryItem(name: parameter, value: "C160982 / A&B")])
        }
        XCTAssertNil(Supplier.searchURL(spn: "123", supplier: "Custom supplier"))
        XCTAssertNil(Supplier.searchURL(spn: " ", supplier: "LCSC"))
    }
    func testLegacyDataAndCanonicalEncoding() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Part())) as? [String: Any])
        json.removeValue(forKey: "spn"); json.removeValue(forKey: "supplier")
        json["lcsc"] = "C123"
        let part = try JSONDecoder().decode(Part.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(part.spn, "C123"); XCTAssertEqual(part.supplier, "LCSC")
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(part)) as? [String: Any])
        XCTAssertEqual(encoded["spn"] as? String, "C123"); XCTAssertNil(encoded["lcsc"])
        let request = try JSONDecoder().decode(ProjectBOMItem.self, from: Data("{\"designators\":\"C1\",\"package\":\"0402\",\"quantity\":1,\"value\":\"CAP\",\"lcsc\":\"C123\"}".utf8))
        XCTAssertEqual(request.spn, "C123"); XCTAssertEqual(request.supplier, "LCSC")
    }

    @MainActor func testSupplierScopedMatchingAndAPIValidation() throws {
        let store = InventoryStore(repository: try SQLiteRepository(path: ":memory:"))
        var first = Part(); first.number = "A"; first.spn = "123"; first.supplier = "LCSC"; first.stock = 2
        var second = Part(); second.number = "B"; second.spn = "123"; second.supplier = "DigiKey"; second.stock = 3
        try store.importParts([first, second])
        XCTAssertEqual(store.parts.count, 2)
        second.number = "Alternative"; second.stock = 4; second.supplier = "digi-key"
        try store.importParts([second])
        XCTAssertEqual(store.parts.count, 2)
        XCTAssertEqual(store.parts.first { $0.number == "B" }?.stock, 7)
        let request = ProjectBOMItem(designators: "C1", package: "", quantity: 1, value: "UNKNOWN", spn: "123", supplier: "LCSC")
        XCTAssertEqual(ProjectBOMMatcher.candidates(for: request, parts: store.parts).map(\.number), ["A"])
        var purchase = PurchaseItem(); purchase.part = first
        try store.addPurchase(purchase)
        purchase.part = second
        try store.addPurchase(purchase)
        XCTAssertEqual(store.purchases.count, 2)
        let router = InventoryAPIRouter(store: store)
        func post(_ data: [String: Any]) throws -> APIResponse {
            router.handle(method: "POST", target: "/v1/parts", body: try JSONSerialization.data(withJSONObject: data))
        }
        XCTAssertEqual(try post(["number": "Missing supplier", "spn": "ABC"]).status, 400)
        XCTAssertEqual(try post(["number": "Mouser part", "spn": "ABC", "supplier": "Mouser"]).status, 201)
        XCTAssertEqual(try post(["number": "Legacy API", "lcsc": "C999"]).status, 201)
        XCTAssertEqual(store.parts.first { $0.number == "Legacy API" }?.supplier, "LCSC")
    }

    func testSupplierCSVColumnsAndImport() throws {
        let document = try BOMImport(text: "Part Number,LCSC,DigiKey,Quantity\nA,C123,,2\nB,,123-ND,3", filename: "suppliers.csv")
        let parts = try document.selectedParts()
        XCTAssertEqual(parts.map(\.supplier), ["LCSC", "DigiKey"])
        let items = parts.map { part -> PurchaseItem in var item = PurchaseItem(); item.part = part; return item }
        let csv = try CSVReader.read(PurchaseCSV.encode(items))
        let lcsc = try XCTUnwrap(csv[0].firstIndex(of: "LCSC"))
        let digiKey = try XCTUnwrap(csv[0].firstIndex(of: "DigiKey"))
        XCTAssertFalse(csv[0].contains("SPN"))
        XCTAssertEqual(csv[1][lcsc], "C123"); XCTAssertEqual(csv[1][digiKey], "")
        XCTAssertEqual(csv[2][lcsc], ""); XCTAssertEqual(csv[2][digiKey], "123-ND")
        XCTAssertThrowsError(try BOMImport(text: "Part Number,SPN\nA,123", filename: "invalid.csv").selectedParts())
        XCTAssertThrowsError(try BOMImport(text: "Part Number,LCSC,SPN,Supplier\nA,C123,123,Mouser", filename: "invalid.csv").selectedParts())
        XCTAssertThrowsError(try BOMImport(text: "Part Number,Supplier,LCSC\nA,Mouser,C123", filename: "invalid.csv").selectedParts())
        let project = try ProjectBOMImport(text: "Designator,Footprint,Quantity,Value,Mouser\nR1,0402,1,MPN,123", filename: "bom.csv", parts: [])
        XCTAssertEqual(project.rows.first?.item.supplier, "Mouser")
    }
}
