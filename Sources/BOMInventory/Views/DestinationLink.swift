import SwiftUI

/// A compact navigation link with a reserved hover affordance to avoid layout shifts.
struct DestinationLink: View {
    var title: String
    var destination: String
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.yellow).opacity(hovering ? 1 : 0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help("Open \(destination): \(title)")
            .accessibilityLabel("Open \(destination): \(title)")
    }
}

struct InventoryNavigation {
    var project: (String) -> Void = { _ in }
    var storage: (String) -> Void = { _ in }
}
private struct InventoryNavigationKey: EnvironmentKey {
    static let defaultValue = InventoryNavigation()
}
extension EnvironmentValues {
    var inventoryNavigation: InventoryNavigation {
        get { self[InventoryNavigationKey.self] }
        set { self[InventoryNavigationKey.self] = newValue }
    }
}
