import SwiftUI

struct LabelFilterPopover: View {
    var labels: [String]
    @Binding var selected: Set<String>
    @State private var query = ""
    private var matching: [String] {
        labels.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filter by labels").font(.headline)
                Spacer()
                Button("Clear all") { selected.removeAll() }.buttonStyle(.plain).foregroundStyle(Theme.yellow).disabled(selected.isEmpty)
            }
            Text("Show parts matching any selected label.").font(.caption).foregroundStyle(Theme.muted)
            if !selected.isEmpty {
                LabelChips(labels: selected.sorted()) { selected.remove($0) }
            }
            TextField("Search labels…", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matching, id: \.self) { label in
                        Toggle(label, isOn: Binding(get: { selected.contains(label) }, set: {
                            if $0 { selected.insert(label) } else { selected.remove(label) }
                        })).toggleStyle(.checkbox).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if matching.isEmpty { Text("No labels found").foregroundStyle(Theme.muted).padding(.vertical, 12) }
                }
            }.frame(height: 220)
        }.padding(16).frame(width: 320).background(Theme.panel)
    }
}
