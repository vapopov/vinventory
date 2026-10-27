import SwiftUI

/// Reusable detailed popover. Resolve by ID so inventory changes remain live.
struct PartPreview: View {
    var store: InventoryStore
    var partID: String
    var dismiss: () -> Void
    var editPart: (Part) -> Void
    var showPart: (Part) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PART PREVIEW").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).accessibilityLabel("Close Part Preview")
            }.padding(.horizontal, 16).frame(height: 34).background(Theme.raised)
            if let part = store.parts.first(where: { $0.id == partID }) {
                ScrollView {
                    PartSummaryView(store: store, part: part, available: store.available(part), allocated: store.allocated(part), projects: store.projectCount(part), edit: {
                        dismiss()
                        editPart(part)
                    }, beforeNavigate: dismiss)
                }
                HStack {
                    Spacer()
                    Button { dismiss(); showPart(part) } label: { Label("Go to Part", systemImage: "arrow.right") }
                        .buttonStyle(.plain).foregroundStyle(Theme.yellow)
                }.padding(.horizontal, 20).frame(height: 38).background(Theme.raised)
            } else {
                EmptyState(title: "Part unavailable", subtitle: "This part is no longer in the inventory.")
            }
        }.frame(width: 560, height: 420).font(.system(size: 13)).background(Theme.panel)
            .preferredColorScheme(.dark).accessibilityElement(children: .contain).accessibilityLabel("Part Preview")
            .onExitCommand(perform: dismiss)
    }
}

/// A value wrapper lets table popovers supply a safe, reusable dismissal callback.
struct PartPreviewDismissAction {
    var action: () -> Void
    func callAsFunction() { action() }
}
