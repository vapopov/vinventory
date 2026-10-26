import Foundation
import Network

struct HTTPRequest {
    var method: String
    var target: String
    var body: Data
    static let limit = 1_048_576
    static func parse(_ data: Data) throws -> HTTPRequest? {
        guard data.count <= limit else { throw HTTPParseError.invalid }
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let header = String(data: data[..<range.lowerBound], encoding: .utf8) else { throw HTTPParseError.invalid }
        let lines = header.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, ["HTTP/1.1", "HTTP/1.0"].contains(String(start[2])) else { throw HTTPParseError.invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw HTTPParseError.invalid }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { throw HTTPParseError.invalid }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw HTTPParseError.invalid }
        if ["POST", "PATCH"].contains(String(start[0])) {
            guard headers["content-type"]?.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) == "application/json" else { throw HTTPParseError.invalid }
        }
        let length: Int
        if let raw = headers["content-length"] {
            guard let count = Int(raw), count >= 0, count <= limit else { throw HTTPParseError.invalid }; length = count
        } else { length = 0 }
        guard data.count - range.upperBound >= length else { return nil }
        return HTTPRequest(method: String(start[0]), target: String(start[1]), body: data.subdata(in: range.upperBound..<(range.upperBound + length)))
    }
}
enum HTTPParseError: Error { case invalid }

final class HTTPConnection {
    let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: (HTTPRequest, @escaping (APIResponse) -> Void) -> Void
    private var buffer = Data()
    private var replied = false
    private var timer: DispatchWorkItem?
    init(_ connection: NWConnection, queue: DispatchQueue, handler: @escaping (HTTPRequest, @escaping (APIResponse) -> Void) -> Void) {
        self.connection = connection; self.queue = queue; self.handler = handler
    }
    func start() {
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { [weak self] in self?.connection.cancel() }
        timer = timeout; queue.asyncAfter(deadline: .now() + 15, execute: timeout)
        receive()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            if let data { buffer.append(data) }
            do {
                if let request = try HTTPRequest.parse(buffer) {
                    guard !replied else { return }; replied = true
                    handler(request) { [self] response in queue.async { self.send(response) } }
                } else if complete || error != nil { connection.cancel() }
                else { receive() }
            } catch { send(APIResponse(status: 400, data: Data("{\"error\":\"Invalid or oversized HTTP request\"}".utf8))) }
        }
    }
    private func send(_ response: APIResponse) {
        let reasons = [200: "OK", 201: "Created", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error"]
        var bytes = Data("HTTP/1.1 \(response.status) \(reasons[response.status] ?? "Error")\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(response.data.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        bytes.append(response.data)
        connection.send(content: bytes, completion: .contentProcessed { [self] _ in timer?.cancel(); connection.cancel() })
    }
}
