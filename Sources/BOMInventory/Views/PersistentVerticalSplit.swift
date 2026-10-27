import SwiftUI
import AppKit

/// Keeps the divider's proportion independent of the selected item and window size.
struct PersistentVerticalSplit<Top: View, Bottom: View>: View {
    @AppStorage private var savedFraction: Double
    @State private var dragStart: Double?
    @State private var dragFraction: Double?
    private let top: Top
    private let bottom: Bottom

    init(key: String, @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        _savedFraction = AppStorage(wrappedValue: 0.6, key)
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - 6)
            let minimum = min(200, height / 2)
            let maximum = max(minimum, height - min(120, height / 2))
            let fraction = dragFraction ?? savedFraction
            let topHeight = min(maximum, max(minimum, height * fraction))
            VStack(spacing: 0) {
                top.frame(height: topHeight)
                Rectangle().fill(Theme.raised).frame(height: 6)
                    .overlay { Rectangle().fill(Theme.muted.opacity(0.4)).frame(height: 1) }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard height > 0 else { return }
                            if dragStart == nil { dragStart = topHeight / height }
                            dragFraction = min(maximum / height, max(minimum / height, (dragStart ?? 0.6) + value.translation.height / height))
                        }
                        .onEnded { _ in
                            if let dragFraction { savedFraction = dragFraction }
                            dragStart = nil; dragFraction = nil
                        })
                    .accessibilityLabel("Resize project purchases")
                    .accessibilityValue("\(Int((height > 0 ? topHeight / height : 0.6) * 100)) percent details")
                    .accessibilityAdjustableAction { direction in
                        guard height > 0 else { return }
                        savedFraction = min(maximum / height, max(minimum / height, topHeight / height + (direction == .increment ? 0.05 : -0.05)))
                    }
                bottom.frame(height: max(0, height - topHeight))
            }
        }
    }
}
