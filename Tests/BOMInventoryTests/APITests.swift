import XCTest
import Network
@testable import BOMInventory

final class APITests: XCTestCase {
    func testHTTPFraming() throws {
        let header = "POST /v1/parts HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n"
        XCTAssertNil(try HTTPRequest.parse(Data((header + "{").utf8)))
        let parsed = try XCTUnwrap(HTTPRequest.parse(Data((header + "{}").utf8)))
        XCTAssertEqual(parsed.method, "POST"); XCTAssertEqual(parsed.body, Data("{}".utf8))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n{}".utf8)))
    }
    func testHTTPServerOverLoopback() async throws {
        let queue = DispatchQueue(label: "api-test")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "Listener ready")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            let client = HTTPConnection(connection, queue: queue) { request, respond in
                respond(APIResponse(status: 200, data: request.body))
            }
            client.start()
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port.rawValue)/v1/parts")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"number\":\"ABC\"}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, request.httpBody)
    }
    @MainActor func testPartsProjectsAllocationsAndRequests() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = InventoryStore(repository: try SQLiteRepository(path: path))
        let router = InventoryAPIRouter(store: store)
        func call(_ method: String, _ path: String, _ body: [String: Any] = [:]) throws -> APIResponse {
            router.handle(method: method, target: path, body: try JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(try call("GET", "/health").status, 200)
        XCTAssertEqual(try call("POST", "/v1/parts", ["number": "CAP", "stock": 10, "labels": ["Capacitor"], "customFields": ["Voltage": "50V"]]).status, 201)
        let part = try XCTUnwrap(store.parts.first)
        XCTAssertEqual(try call("PATCH", "/v1/parts/" + part.id, ["description": "Updated"]).status, 200)
        XCTAssertEqual(store.parts.first?.description, "Updated")
        XCTAssertEqual(try call("POST", "/v1/projects", ["name": "Board A", "description": "Demo"]).status, 201)
        let projectPath = "/v1/projects/Board%20A"
        XCTAssertEqual(try call("POST", projectPath + "/allocations", ["partID": part.id, "quantity": 2, "designators": "C1, C2"]).status, 201)
        let allocation = try XCTUnwrap(store.allocations.first)
        XCTAssertEqual(try call("PATCH", projectPath + "/allocations/" + allocation.id, ["quantity": 3]).status, 200)
        XCTAssertEqual(try call("PATCH", "/v1/parts/" + part.id, ["stock": 1]).status, 400)
        XCTAssertEqual(try call("POST", projectPath + "/allocations", ["partID": part.id, "quantity": true]).status, 400)
        XCTAssertEqual(try call("POST", projectPath + "/requested", ["value": "Missing", "quantity": 4, "designators": "U1-U4"]).status, 201)
        let request = try XCTUnwrap(store.bomEntries(for: "Board A").first)
        XCTAssertEqual(try call("PATCH", projectPath + "/requested/" + request.id, ["quantity": 6]).status, 200)
        XCTAssertEqual(store.bomEntries(for: "Board A").first?.item.quantity, 6)
        XCTAssertEqual(try call("GET", projectPath + "/requested").status, 200)
        XCTAssertEqual(try call("DELETE", projectPath + "/requested/" + request.id).status, 200)
        XCTAssertTrue(store.bomEntries(for: "Board A").isEmpty)
        XCTAssertEqual(try call("DELETE", projectPath + "/allocations/" + allocation.id).status, 200)
        XCTAssertEqual(store.available(part), 10)
        XCTAssertEqual(try call("PATCH", projectPath, ["name": "Renamed"]).status, 200)
        XCTAssertEqual(try call("DELETE", "/v1/projects/Renamed").status, 200)
        XCTAssertEqual(try call("DELETE", "/v1/parts/" + part.id).status, 200)
        XCTAssertEqual(try call("GET", "/v1/parts/" + part.id).status, 404)
        XCTAssertEqual(router.handle(method: "POST", target: "/v1/parts", body: Data("broken".utf8)).status, 400)
    }
}
