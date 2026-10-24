import SwiftUI
struct PartEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var part: Part
    var store: InventoryStore
    @State private var customFields: [CustomFieldDraft]
    @State private var labelDraft = ""
    var save: (Part) throws -> Void
    @State private var error: String?
    @State private var attachmentDraft = AttachmentDraft()
    @State private var downloadingDatasheet = false
    init(part: Part, store: InventoryStore, save: @escaping (Part) throws -> Void) {
        _part = State(initialValue: part)
        _customFields = State(initialValue: part.customFields.sorted { $0.key < $1.key }.map { CustomFieldDraft(name: $0.key, value: $0.value) })
        self.save = save
        self.store = store
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Part details").font(.title2.bold()); Spacer(); Image(systemName: "cpu").foregroundStyle(Theme.yellow) }
            ScrollView {
                Form {
                    LabeledContent("Image") { PartImageEditor(image: $part.image, draft: attachmentDraft) }
                    TextField("Part number", text: $part.number)
                    TextField("LCSC", text: $part.lcsc).help("Optional LCSC supplier part number, for example C105871.")
                    LabeledContent("Manufacturer") {
                        SuggestionField(text: $part.manufacturer, placeholder: "", suggestions: store.manufacturers, filterOnTyping: true, choose: { part.manufacturer = $0 }, submit: {}).accessibilityLabel("Manufacturer")
                            .help("Choose a recent manufacturer or type a new one.")
                    }
                    LabeledContent("Labels") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabelChips(labels: part.labels) { label in part.labels.removeAll { $0 == label } }
                            SuggestionField(text: $labelDraft, placeholder: "", suggestions: store.labelSuggestions(for: labelDraft, excluding: part.labels), keepFocusAfterChoice: true, choose: { addLabel($0) }, submit: { addLabel(labelDraft) }).accessibilityLabel("Labels")
                            Text("Return adds a label • Recent labels appear when focused").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                    }
                    TextField("Description", text: $part.description, axis: .vertical).lineLimit(2...4)
                    Button("Analyze description") {
                        DescriptionAnalysis.analyze(part.description, valueHint: part.value).fillingMissing(in: &part)
                    }.buttonStyle(.plain).foregroundStyle(Theme.yellow)
                        .help("Fill missing value and tolerance and add a component label from the description.")
                    LabeledContent("Package") {
                        SuggestionField(text: $part.package, placeholder: "", suggestions: store.packages, filterOnTyping: true, choose: { part.package = $0 }, submit: {}).accessibilityLabel("Package")
                            .help("Choose a recent package or type a new one.")
                    }
                    TextField("Value", text: $part.value)
                    LabeledContent("Tolerance") {
                        VStack(alignment: .leading, spacing: 4) {
                            SuggestionField(text: $part.tolerance, placeholder: "", suggestions: ["1%", "5%", "10%", "20%"], choose: { part.tolerance = $0 }, submit: {}).accessibilityLabel("Tolerance")
                            Text("Choose a preset or enter a custom tolerance.").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                    }
                    LabeledContent("Storage") {
                        SuggestionField(text: $part.storage, placeholder: "", suggestions: store.storageSuggestions, filterOnTyping: true, choose: { part.storage = $0 }, submit: {}).accessibilityLabel("Storage")
                            .help("Choose a recent storage location or type a new one.")
                    }
                    TextField("On-hand stock", value: $part.stock, format: .number)
                    LabeledContent("Datasheet") { DatasheetEditor(value: $part.datasheet, downloading: $downloadingDatasheet, draft: attachmentDraft) }
                    CustomFieldsEditor(fields: $customFields)
                    LabeledContent("Barcode") { Text(part.barcode).font(.system(size: 10, design: .monospaced)).textSelection(.enabled) }
                }.textFieldStyle(.roundedBorder)
            }.frame(maxHeight: 540)
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save part") { do {
                if !labelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try commitLabel(labelDraft) }
                part.customFields = try CustomFieldDraft.dictionary(customFields)
                try save(part); dismiss()
            } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).tint(Theme.purple).disabled(downloadingDatasheet) }
        }.padding(26).frame(width: 590).background(Theme.panel).suggestionOverlay()
        .onDisappear { attachmentDraft.discard() }
    }
    private func addLabel(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try commitLabel(value); error = nil } catch { self.error = error.localizedDescription }
    }
    private func commitLabel(_ value: String) throws {
        let canonical = try store.labelName(for: value)
        if !part.labels.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) { part.labels.append(canonical) }
        labelDraft = ""
    }
}
