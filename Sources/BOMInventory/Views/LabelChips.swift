import SwiftUI
struct LabelChips: View {
    var labels: [String]
    var remove: ((String) -> Void)?
    var body: some View {
        LabelFlow(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                HStack(spacing: 6) {
                    Text(label).lineLimit(1).help(label)
                    if let remove {
                        Button { remove(label) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.plain).accessibilityLabel("Remove label \(label)")
                    }
                }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.purple, in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}
private struct LabelFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 480).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, position) in arrangement.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if x > 0 && x + itemWidth > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: subviews.isEmpty ? 0 : y + rowHeight), positions)
    }
}
