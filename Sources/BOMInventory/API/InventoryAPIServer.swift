import Foundation
import Combine
import Network

@MainActor final class InventoryAPIServer: ObservableObject {
    @Published var address: String
    @Published var port: String
    @Published private(set) var running = false
    @Published private(set) var status = "Stopped"
    private let store: InventoryStore
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.local.BOMInventory.http")
    private var clients: [UUID: HTTPConnection] = [:]
    private var generation = UUID()
    init(store: InventoryStore) {
        self.store = store
        address = UserDefaults.standard.string(forKey: "api.address") ?? "127.0.0.1"
        port = UserDefaults.standard.string(forKey: "api.port") ?? "8080"
        if UserDefaults.standard.bool(forKey: "api.enabled") { start() }
    }
    func start() {
        stop(persist: false)
        guard let number = UInt16(port), number > 0, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Enter an address and a port from 1–65535."; return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: NWEndpoint.Port(rawValue: number)!)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            let token = generation
            status = "Starting…"
            UserDefaults.standard.set(address, forKey: "api.address")
            UserDefaults.standard.set(port, forKey: "api.port")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    switch state {
                    case .ready: self.running = true; self.status = "Listening"; UserDefaults.standard.set(true, forKey: "api.enabled")
                    case .failed(let error): self.stop(); self.status = error.localizedDescription
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == token else { connection.cancel(); return }
                    let id = UUID()
                    let client = HTTPConnection(connection, queue: self.queue) { [weak self] request, respond in
                        Task { @MainActor in
                            guard let self, self.generation == token else { connection.cancel(); return }
                            respond(InventoryAPIRouter(store: self.store).handle(method: request.method, target: request.target, body: request.body))
                        }
                    }
                    self.clients[id] = client
                    connection.stateUpdateHandler = { [weak self] state in
                        if case .cancelled = state { Task { @MainActor in self?.clients.removeValue(forKey: id) } }
                    }
                    client.start()
                }
            }
            listener.start(queue: queue)
        } catch { status = error.localizedDescription }
    }
    func stop(persist: Bool = true) {
        generation = UUID(); listener?.cancel(); listener = nil
        for client in clients.values { client.connection.cancel() }; clients.removeAll()
        running = false; status = "Stopped"
        if persist { UserDefaults.standard.set(false, forKey: "api.enabled") }
    }
}
