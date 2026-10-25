import SwiftUI

struct RequestSyncReview: View {
    var store: InventoryStore
    var entries: [ProjectBOMEntry]
    @Binding var matches: [String: String]

    private func allocationCount(for entry: ProjectBOMEntry, part: Part) -> Int {
        var budget = max(0, store.available(part))
        // Use the same request order as Apply, including selections hidden by search.
        for earlier in store.bomEntries(for: entry.project) {
            if earlier.id == entry.id { break }
            if matches[earlier.id] == part.id { budget -= min(max(0, budget), store.requestedQuantity(earlier)) }
        }
        return min(store.requestedQuantity(entry), max(0, budget))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Check one match per request, then Apply to allocate available stock.")
                .font(.caption).foregroundStyle(Theme.muted).padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REQUEST • \(entry.item.designators)").fontWeight(.semibold)
                                Text("Qty \(store.requestedQuantity(entry)) • \(entry.item.value) • \(entry.item.package) • \(entry.item.lcsc)")
                            }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.raised)
                            let candidates = store.requestCandidates(entry)
                            ForEach(candidates) { part in
                                HStack(spacing: 12) {
                                    Toggle("Allocate \(part.number)", isOn: Binding(get: { matches[entry.id] == part.id }, set: { matches[entry.id] = $0 ? part.id : nil }))
                                        .labelsHidden().accessibilityLabel("Allocate match \(part.number) for \(entry.item.designators)")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(part.number) • \(part.manufacturer)").fontWeight(.medium)
                                        Text("\(part.value) • \(part.package) • Available \(store.available(part)) • \(allocationCount(for: entry, part: part)) to allocate").foregroundStyle(Theme.muted)
                                        Text(part.description).foregroundStyle(Theme.muted).lineLimit(2)
                                    }
                                    Spacer()
                                }.font(.system(size: 12)).padding(10)
                                    .background(matches[entry.id] == part.id ? Theme.selection : Theme.panel)
                                    .contentShape(Rectangle()).onTapGesture {
                                        matches[entry.id] = matches[entry.id] == part.id ? nil : part.id
                                    }
                            }
                            if candidates.isEmpty { Text("No matching inventory parts").font(.caption).foregroundStyle(Theme.muted).padding(10) }
                        }.background(Theme.panel)
                    }
                }.padding(12)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
