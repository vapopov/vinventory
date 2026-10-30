import SwiftUI

struct BackupButton: View {
    let store: InventoryStore
    @ObservedObject private var backup = ResticBackup.shared
    @State private var showingPopover = false
    @State private var configuring = false
    @State private var passwordRequest: BackupPasswordRequest?
    var body: some View {
        Button {
            backup.refresh()
            showingPopover.toggle()
        } label: {
            Label("Backup", systemImage: "externaldrive.badge.timemachine")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(backup.executable != nil && !backup.destinations.isEmpty ? Color.orange : Color.gray, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain).help("Configure and run restic backups")
        .popover(isPresented: $showingPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inventory backup").font(.headline)
                if backup.executable == nil {
                    Text("restic must be installed. It is required for the backup feature.")
                    Text("Install restic, then reopen this popup. Homebrew: brew install restic").font(.caption).foregroundStyle(Theme.muted)
                } else {
                    Text(backup.busy ? "Operation in progress…" : "\(backup.destinations.count) configured repositories")
                    ForEach(backup.destinations) { destination in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(destination.repository).lineLimit(1).truncationMode(.middle)
                            if let date = destination.lastBackup {
                                Text("Last successful backup: \(date.formatted(date: .abbreviated, time: .shortened))")
                            } else { Text("No successful backup recorded by this app") }
                        }.font(.caption)
                    }
                    HStack {
                        Button("Configure") { showingPopover = false; configuring = true }
                        Button("Sync") { showingPopover = false; passwordRequest = BackupPasswordRequest(destinationID: nil) }
                            .disabled(backup.destinations.isEmpty)
                    }.disabled(backup.busy).buttonStyle(ProjectBOMActionStyle())
                    if !backup.output.isEmpty {
                        ScrollView { Text(backup.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(height: 200)
                    }
                }
            }.padding(18).frame(width: 460).background(Theme.panel)
        }
        .sheet(isPresented: $configuring) {
            BackupConfiguration(backup: backup) { id in
                configuring = false
                passwordRequest = BackupPasswordRequest(destinationID: id)
            }
        }
        .sheet(item: $passwordRequest) { request in
            BackupPasswordDialog(initializing: request.destinationID != nil) { password in
                passwordRequest = nil
                backup.start(password: password, initializing: request.destinationID, store: store)
                showingPopover = true
            }
        }
        .alert("Backup error", isPresented: Binding(get: { backup.error != nil }, set: { if !$0 { backup.error = nil } })) {
            Button("OK") { backup.error = nil }
        } message: { Text(backup.error ?? "") }
    }
}

private struct BackupPasswordRequest: Identifiable {
    let id = UUID()
    let destinationID: UUID?
}

private struct BackupPasswordDialog: View {
    let initializing: Bool
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(initializing ? "Initialize repository" : "Back up inventory").font(.headline)
            Text(initializing ? "Choose a password for this repository. Keep it safe; restoring requires it." : "Enter the repository password. The same password will be used for every configured destination, one at a time.")
            SecureField("Repository password", text: $password)
            if initializing { SecureField("Confirm password", text: $confirmation) }
            Text("The password is passed through RESTIC_PASSWORD for this operation and is not saved.").font(.caption).foregroundStyle(Theme.muted)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { password = ""; confirmation = ""; dismiss() }
                Button(initializing ? "Initialize" : "Sync") {
                    let value = password
                    password = ""; confirmation = ""
                    submit(value)
                }.keyboardShortcut(.defaultAction).disabled(password.isEmpty || (initializing && password != confirmation))
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 460)
    }
}

private struct BackupConfiguration: View {
    @ObservedObject var backup: ResticBackup
    let initialize: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [BackupDestination]
    @State private var error: String?
    init(backup: ResticBackup, initialize: @escaping (UUID) -> Void) {
        self.backup = backup
        self.initialize = initialize
        _destinations = State(initialValue: backup.destinations)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup repositories").font(.title2)
            Text("Backups include the inventory database and managed attachments. Add existing repositories, or initialize a new repository before Sync.")
            ScrollView {
                VStack(spacing: 18) {
                    ForEach($destinations) { $destination in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Destination").font(.headline)
                                Spacer()
                                Button("Initialize…") {
                                    do { try backup.save(destinations); initialize(destination.id) }
                                    catch { self.error = error.localizedDescription }
                                }
                                Button("Remove", role: .destructive) { destinations.removeAll { $0.id == destination.id } }
                            }
                            TextField("s3:https://server:port/bucket_name", text: $destination.repository)
                                .onChange(of: destination.repository) { _, _ in destination.lastBackup = nil }
                            Text("Environment credentials — one ENV_NAME=ENV_VALUE per line").font(.caption)
                            TextEditor(text: $destination.environment).font(.system(size: 12, design: .monospaced)).frame(height: 95)
                                .border(Theme.muted.opacity(0.3))
                        }.padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }.frame(minHeight: 180, maxHeight: 430)
            Text("Values are literal: no shell expansion or quote removal. Credentials are saved locally in an owner-readable settings file. Repository passwords are requested separately.")
                .font(.caption).foregroundStyle(Theme.muted)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Add repository") { destinations.append(BackupDestination()) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    do { try backup.save(destinations); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 640)
    }
}
