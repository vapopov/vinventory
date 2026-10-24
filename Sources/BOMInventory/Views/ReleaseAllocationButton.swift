import SwiftUI

struct ReleaseAllocationButton: View {
    var title: String
    var release: () -> Void
    @State private var confirming = false
    var body: some View {
        HStack(spacing: 14) {
            if confirming {
                Button { confirming = false } label: { Image(systemName: "xmark") }.help("Cancel release").accessibilityLabel("Cancel release for \(title)")
                Button { confirming = false; release() } label: { Image(systemName: "checkmark") }.help("Approve release").accessibilityLabel("Approve release for \(title)")
            } else {
                Button("Release") { confirming = true }.accessibilityLabel("Release allocation for \(title)")
            }
        }.buttonStyle(.plain).foregroundStyle(Theme.yellow).font(.system(size: 12))
    }
}
