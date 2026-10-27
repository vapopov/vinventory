// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BOMInventory", platforms: [.macOS(.v14)], products: [.executable(name: "BOMInventory", targets: ["BOMInventory"])], targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"), .executableTarget(name: "BOMInventory", dependencies: ["CSQLite"], resources: [.copy("Resources/KaTeX")], swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "BOMInventoryTests", dependencies: ["BOMInventory"])])
