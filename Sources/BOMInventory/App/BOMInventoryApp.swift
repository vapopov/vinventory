import SwiftUI
import AppKit
@main struct BOMInventoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: InventoryStore?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup("BOM Inventory") {
            Group {
                if let store { ContentView(store: store) }
                else if let startupError { EmptyState(title: "Database unavailable", subtitle: startupError) }
                else { ProgressView().task { openDatabase() } }
            }
            .frame(minWidth: 1120, minHeight: 700).preferredColorScheme(.dark)
        }.defaultSize(width: 1440, height: 860)
    }
    @MainActor private func openDatabase() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("BOMInventory", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = InventoryStore(repository: try SQLiteRepository(path: directory.appendingPathComponent("inventory.sqlite").path), attachmentStorage: AttachmentStorage(root: directory.appendingPathComponent("Attachments", isDirectory: true)))
        } catch { startupError = error.localizedDescription }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
