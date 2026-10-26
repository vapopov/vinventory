import SwiftUI

struct APISettingsPopover: View {
    @ObservedObject var server: InventoryAPIServer
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HTTP API server").font(.headline)
            TextField("Address", text: $server.address)
            TextField("Port", text: $server.port)
            Text(server.status).font(.caption).foregroundStyle(server.running ? Theme.green : Theme.muted)
            Text("HTTP • No authentication").font(.caption).foregroundStyle(Theme.muted)
            HStack {
                Button(server.running ? "Apply & restart" : "Start server") { server.start() }
                if server.running { Button("Stop") { server.stop() } }
            }.buttonStyle(ProjectBOMActionStyle())
        }.textFieldStyle(.roundedBorder).padding(18).frame(width: 320).background(Theme.panel)
    }
}
