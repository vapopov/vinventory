import SwiftUI

struct BOMImportView: View {
    @State var document: BOMImport
    var store: InventoryStore
    var finish: () -> Void
    @State private var labelDrafts: [UUID: String] = [:]
    @State private var error: String?
    private var selectedCount: Int { document.rows.filter(\.selected).count }
    private func columnWidth(_ column: Int) -> CGFloat { BOMImport.field(for: document.headers[column]) == "labels" ? 240 : 180 }
    private var labelSuggestions: [String] {
        let column = document.headers.firstIndex { BOMImport.field(for: $0) == "labels" }
        let importedLabels = column.map { index in document.rows.flatMap { BOMImport.parseLabels($0.values[index]) } } ?? []
        var names: [String] = []
        for label in store.labels + importedLabels where !names.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) { names.append(label) }
        return names
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import parts — \(document.filename)").font(.title2.bold())
            Text("Edit any cell and uncheck rows to skip. Matching part or LCSC numbers increase stock; other rows create new parts. Unknown columns become custom fields.").foregroundStyle(Theme.muted)
            HStack {
                Button("Select all") { for i in document.rows.indices { document.rows[i].selected = true } }
                Button("Deselect all") { for i in document.rows.indices { document.rows[i].selected = false } }
                Text("\(selectedCount) of \(document.rows.count) selected").foregroundStyle(Theme.muted)
            }
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(document.rows.indices, id: \.self) { row in
                            HStack(spacing: 1) {
                                Toggle("Import row \(row + 1)", isOn: $document.rows[row].selected).labelsHidden().frame(width: 46)
                                Text("\(row + 1)").foregroundStyle(Theme.muted).frame(width: 35)
                                ForEach(document.headers.indices, id: \.self) { column in
                                    if BOMImport.field(for: document.headers[column]) == "labels" {
                                        ImportLabelsCell(labels: Binding(get: { BOMImport.parseLabels(document.rows[row].values[column]) }, set: { document.setValue($0.joined(separator: ", "), row: row, column: column) }), pending: Binding(get: { labelDrafts[document.rows[row].id] ?? "" }, set: { labelDrafts[document.rows[row].id] = $0 }), suggestions: labelSuggestions, rowNumber: row + 1)
                                            .frame(width: columnWidth(column))
                                    } else {
                                        TextField(document.headers[column], text: Binding(get: { document.rows[row].values[column] }, set: { document.setValue($0, row: row, column: column) }))
                                            .textFieldStyle(.plain).padding(7).frame(width: columnWidth(column))
                                            .accessibilityLabel("Row \(row + 1), \(document.headers[column])")
                                            .opacity(document.ignoredCustomColumns.contains(column) ? 0.35 : 1)
                                    }
                                }
                            }.frame(minHeight: 34).background(row.isMultiple(of: 2) ? Theme.row : Theme.panel)
                        }
                    } header: {
                        HStack(spacing: 1) {
                            Text("Import").frame(width: 46)
                            Text("#").frame(width: 35)
                            ForEach(document.headers.indices, id: \.self) { column in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.headers[column]).lineLimit(1)
                                    if BOMImport.field(for: document.headers[column]) == nil {
                                        Toggle("Custom field", isOn: Binding(get: { !document.ignoredCustomColumns.contains(column) }, set: { included in
                                            if included { document.ignoredCustomColumns.remove(column) } else { document.ignoredCustomColumns.insert(column) }
                                        })).toggleStyle(.checkbox).font(.caption2).foregroundStyle(Theme.yellow)
                                            .accessibilityLabel("Import custom field \(document.headers[column])")
                                    }
                                }.padding(7).frame(width: columnWidth(column), alignment: .leading)
                            }
                        }.font(.system(size: 12, weight: .semibold)).frame(height: 48).background(Theme.raised)
                    }
                }
            }.background(Theme.row)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { finish() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    do {
                        document.commitPendingLabels(labelDrafts, suggestions: labelSuggestions)
                        labelDrafts = [:]
                        try store.importParts(document.selectedParts()); finish()
                    }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(selectedCount == 0)
            }.buttonStyle(ImportActionStyle())
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.panel).suggestionOverlay()
    }
}

private struct ImportActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Theme.yellow.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: RoundedRectangle(cornerRadius: 3))
    }
}
