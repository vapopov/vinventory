import SwiftUI

struct PurchasePartPreview: View {
    var store: InventoryStore
    var itemID: String
    var dismiss: () -> Void
    var edit: (Part) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PART PREVIEW • PURCHASE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close Part Preview")
            }.padding(.horizontal, 16).frame(height: 34).background(Theme.raised)
            if let item = store.purchases.first(where: { $0.id == itemID }) {
                ScrollView {
                    PartSummaryView(part: item.part, available: item.availableQuantity, allocated: item.allocatedQuantity, projects: item.assignments.count, purchaseMode: true, edit: { dismiss(); edit(item.part) }, beforeNavigate: dismiss)
                }
            } else { EmptyState(title: "Purchase unavailable", subtitle: "This item is no longer in the cart.") }
        }.frame(width: 560, height: 420).font(.system(size: 13)).background(Theme.panel)
            .preferredColorScheme(.dark).onExitCommand(perform: dismiss)
    }
}
