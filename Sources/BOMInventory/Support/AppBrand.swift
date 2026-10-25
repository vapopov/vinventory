import AppKit

enum AppBrand {
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "cpu", accessibilityDescription: "BOM Inventory") ?? NSImage()
    }()
}
