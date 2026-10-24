import SwiftUI

/// Pending text belongs to the import view so it survives scrolling and is flushed by Apply.
struct ImportLabelsCell: View {
    @Binding var labels: [String]
    @Binding var pending: String
    var suggestions: [String]
    var rowNumber: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabelChips(labels: labels) { removed in labels.removeAll { $0 == removed } }
            SuggestionField(text: $pending, placeholder: "Add label…", suggestions: suggestions.filter { name in
                !labels.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }, keepFocusAfterChoice: true, filterOnTyping: true, choose: add, submit: { add(pending) })
                .textFieldStyle(.plain).accessibilityLabel("Labels for import row \(rowNumber)")
                .help("Choose a label or type a new label and press Return. Repeat to assign multiple labels.")
        }.padding(7)
    }
    private func add(_ text: String) {
        var updated = labels
        for token in text.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = suggestions.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
            if !name.isEmpty && !updated.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { updated.append(name) }
        }
        labels = updated
        pending = ""
    }
}
