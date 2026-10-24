import SwiftUI
enum Theme {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let panel = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let row = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let raised = Color(red: 0.16, green: 0.16, blue: 0.15)
    static let purple = Color(red: 0.29, green: 0.24, blue: 0.47)
    static let selection = Color(red: 0.26, green: 0.24, blue: 0.39)
    static let yellow = Color(red: 0.96, green: 0.85, blue: 0.43)
    static let muted = Color(red: 0.69, green: 0.68, blue: 0.76)
    static let green = Color(red: 0.28, green: 0.70, blue: 0.57)
}
struct ToolButton: View {
    var symbol: String
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 32).foregroundStyle(Theme.yellow).background(Theme.raised) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}
struct EmptyState: View {
    var title: String
    var subtitle: String
    var body: some View { VStack(spacing: 12) { Image(systemName: "shippingbox").font(.system(size: 36)).foregroundStyle(Theme.yellow); Text(title).font(.title3.bold()); Text(subtitle).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity) }
}
