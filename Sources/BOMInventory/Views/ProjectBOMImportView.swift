import SwiftUI

struct ProjectBOMImportView: View {
    @State var document: ProjectBOMImport
    var project: String
    var store: InventoryStore
    var finish: () -> Void
    var editPart: (Part) -> Void
    var showPart: (Part) -> Void
    @State private var tab = 0
    @State private var error: String?
    private var allRowsDocument: ProjectBOMImport {
        var copy = document
        for index in copy.rows.indices { copy.rows[index].included = true }
        return copy
    }
    private var plan: ProjectBOMPlan? { try? store.planProjectBOM(allRowsDocument, project: project) }
    private var requested: [ProjectBOMPlannedRow] { (plan?.rows ?? document.rows.map { ProjectBOMPlannedRow(review: $0, allocated: 0) }).filter { $0.requested > 0 } }
    private var planError: String? {
        do { _ = try store.planProjectBOM(document, project: project); return nil } catch { return error.localizedDescription }
    }
    private var matched: [Int] { document.rows.indices.filter { !document.rows[$0].candidates.isEmpty } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review project BOM — \(document.filename)").font(.headline)
            Text("Confirm one candidate per CSV row. Unchecked rows and stock shortages go to Requested. Existing designator groups are replaced on Apply.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            HStack {
                Button("Matched (\(matched.count))") { tab = 0 }.buttonStyle(ProjectBOMTabStyle(selected: tab == 0))
                Button("Request (\(requested.count))") { tab = 1 }.buttonStyle(ProjectBOMTabStyle(selected: tab == 1))
                Spacer()
                Text("\(document.rows.filter { $0.selectedPartID != nil }.count) confirmed").foregroundStyle(Theme.muted)
            }.buttonStyle(.plain)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if tab == 0 {
                        ForEach(matched, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 0) {
                                source(document.rows[index].item, title: "CSV ROW \(index + 1)")
                                ForEach(document.rows[index].candidates, id: \.self) { id in
                                    if let part = store.parts.first(where: { $0.id == id }) {
                                        ProjectBOMCandidateRow(part: part, store: store, selected: Binding(get: { document.rows[index].selectedPartID == id }, set: { document.rows[index].selectedPartID = $0 ? id : nil }), editPart: editPart, showPart: showPart)
                                    }
                                }
                                if let row = plan?.rows.first(where: { $0.review.id == document.rows[index].id }), row.review.selectedPartID != nil {
                                    Text("\(row.allocated) to allocate • \(row.requested) to request").font(.caption).foregroundStyle(Theme.muted).padding(10)
                                }
                            }.background(Theme.panel)
                        }
                        if matched.isEmpty { Text("No candidate matches. Open Request to review the missing BOM rows.").foregroundStyle(Theme.muted).padding() }
                    } else {
                        ForEach(requested, id: \.review.id) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Toggle("Include request", isOn: Binding(get: {
                                        document.rows.first { $0.id == row.review.id }?.included ?? true
                                    }, set: { included in
                                        if let index = document.rows.firstIndex(where: { $0.id == row.review.id }) { document.rows[index].included = included }
                                    })).labelsHidden().padding(.leading, 10).accessibilityLabel("Include request \(row.review.item.value)")
                                    source(row.review.item, title: "REQUEST \(row.requested)")
                                }
                                Text(row.review.selectedPartID == nil ? "No confirmed match" : "Insufficient available stock — \(row.allocated) can be allocated")
                                    .font(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 10).padding(.bottom, 10)
                            }.background(Theme.panel)
                        }
                        if requested.isEmpty { Text("All BOM quantities have confirmed matches and available stock.").foregroundStyle(Theme.muted).padding() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let planError { Text(planError).foregroundStyle(.red) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { finish() }
                Button("Apply") {
                    do { try store.applyProjectBOM(document, projectName: project); finish() }
                    catch { self.error = error.localizedDescription }
                }
            }.buttonStyle(ProjectBOMActionStyle())
        }.padding(14).background(Theme.row)
    }
    private func source(_ item: ProjectBOMItem, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title)  •  \(item.designators)").font(.system(size: 12, weight: .semibold))
            Text("Qty \(item.quantity)  •  \(item.value)  •  \(item.package)\(item.lcsc.isEmpty ? "" : "  •  " + item.lcsc)").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.raised)
    }
}
private struct ProjectBOMCandidateRow: View {
    var part: Part
    var store: InventoryStore
    @Binding var selected: Bool
    var editPart: (Part) -> Void
    var showPart: (Part) -> Void
    @State private var preview = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Confirm \(part.number)", isOn: $selected).labelsHidden().accessibilityLabel("Confirm match \(part.number)")
            VStack(alignment: .leading, spacing: 3) {
                Text("\(part.number)  •  \(part.manufacturer)").fontWeight(.medium)
                Text("\(part.value)  •  \(part.package)  •  Available \(store.available(part))\(part.lcsc.isEmpty ? "" : "  •  " + part.lcsc)").foregroundStyle(Theme.muted)
                Text(part.description).foregroundStyle(Theme.muted).lineLimit(2)
            }.font(.system(size: 12))
            Spacer()
            Button("Part Preview") { preview = true }.buttonStyle(.plain).foregroundStyle(Theme.yellow)
                .popover(isPresented: $preview) { PartPreview(store: store, partID: part.id, dismiss: { preview = false }, editPart: editPart, showPart: showPart) }
        }.padding(10).background(selected ? Theme.selection.opacity(0.5) : .clear)
            .contentShape(Rectangle()).onTapGesture { selected.toggle() }
    }
}
struct ProjectBOMActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 18).padding(.vertical, 8)
            .background(Theme.yellow.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 3))
    }
}

struct ProjectBOMTabStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? Color.white : Theme.yellow)
            .padding(.horizontal, 14).frame(height: 40)
            .background(selected ? Theme.purple.opacity(configuration.isPressed ? 0.8 : 1) : Color.clear)
            .contentShape(Rectangle())
    }
}
