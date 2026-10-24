import SwiftUI

/// The field only publishes an anchor. Its menu is drawn above the editor at the root,
/// outside the Form and ScrollView, so suggestions never affect layout or get clipped.
struct SuggestionField: View {
    @Binding var text: String
    var placeholder: String
    var suggestions: [String]
    var keepFocusAfterChoice = false
    var filterOnTyping = false
    var choose: (String) -> Void
    var submit: () -> Void
    @FocusState private var focused: Bool
    @State private var highlighted: Int?
    @State private var dismissed = false
    @State private var editedSinceFocus = false
    private var matches: [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(suggestions.filter {
            !filterOnTyping || !editedSinceFocus || query.isEmpty || $0.localizedCaseInsensitiveContains(query)
        }.prefix(10))
    }
    private var showing: Bool { focused && !dismissed && !matches.isEmpty }
    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .background(FieldClickMonitor { dismissed = false; highlighted = nil })
            .onKeyPress(.downArrow) {
                guard focused, !matches.isEmpty else { return .ignored }
                dismissed = false
                highlighted = min((highlighted ?? -1) + 1, matches.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard showing else { return .ignored }
                highlighted = max((highlighted ?? 1) - 1, 0)
                return .handled
            }
            .onKeyPress(.return) {
                if showing, let highlighted, matches.indices.contains(highlighted) { select(matches[highlighted]) }
                else { submit(); if !keepFocusAfterChoice { dismissed = true } }
                return .handled
            }
            .onKeyPress(.escape) {
                guard showing else { return .ignored }
                dismissed = true
                return .handled
            }
            .anchorPreference(key: SuggestionPreference.self, value: .bounds) { anchor in
                showing ? [SuggestionPresentation(anchor: anchor, values: matches, highlighted: highlighted, select: select, dismiss: { dismissed = true; highlighted = nil })] : []
            }
            .onChange(of: text) { _, _ in
                highlighted = nil
                dismissed = false
                if focused { editedSinceFocus = true }
            }
            .onChange(of: focused) { _, _ in highlighted = nil; dismissed = false; editedSinceFocus = false }
            .onChange(of: suggestions) { _, _ in highlighted = nil }
    }
    private func select(_ suggestion: String) {
        choose(suggestion)
        highlighted = nil
        if !keepFocusAfterChoice { focused = false }
    }
}

private struct SuggestionPresentation {
    var anchor: Anchor<CGRect>
    var values: [String]
    var highlighted: Int?
    var select: (String) -> Void
    var dismiss: () -> Void
}
private struct SuggestionPreference: PreferenceKey {
    static var defaultValue: [SuggestionPresentation] = []
    static func reduce(value: inout [SuggestionPresentation], nextValue: () -> [SuggestionPresentation]) { value += nextValue() }
}

extension View {
    func suggestionOverlay() -> some View {
        overlayPreferenceValue(SuggestionPreference.self) { presentations in
            GeometryReader { geometry in
                if let presentation = presentations.last {
                    let rect = geometry[presentation.anchor]
                    let requestedHeight = CGFloat(presentation.values.count) * 27 + 8
                    let below = max(0, geometry.size.height - rect.maxY - 8)
                    let above = max(0, rect.minY - 8)
                    let opensBelow = below >= requestedHeight || below >= above
                    let height = min(requestedHeight, opensBelow ? below : above)
                    let width = min(max(rect.width, 180), geometry.size.width - 16)
                    let left = max(8, min(rect.minX, geometry.size.width - width - 8))
                    let menuTop = opensBelow ? rect.maxY + 4 : rect.minY - height - 4
                    ZStack(alignment: .topLeading) {
                        OutsideClickMonitor(fieldRect: rect, menuRect: CGRect(x: left, y: menuTop, width: width, height: height), dismiss: presentation.dismiss)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        SuggestionMenu(presentation: presentation)
                            .frame(width: width, height: height)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.muted.opacity(0.3)))
                            .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
                            .offset(x: left, y: menuTop)
                    }
                }
            }
        }
    }
}
private struct SuggestionMenu: View {
    var presentation: SuggestionPresentation
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(presentation.values, id: \.self) { suggestion in
                        let selected = presentation.highlighted.flatMap { presentation.values.indices.contains($0) ? presentation.values[$0] : nil } == suggestion
                        Button { presentation.select(suggestion) } label: {
                            HStack {
                                Text(suggestion).lineLimit(1)
                                Spacer()
                                if selected { Image(systemName: "return").font(.caption) }
                            }.padding(.horizontal, 9).frame(height: 27)
                                .background(selected ? Theme.selection : Color.clear)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).focusable(false).id(suggestion)
                    }
                }.padding(.vertical, 4)
            }
            .onChange(of: presentation.highlighted) { _, index in
                if let index, presentation.values.indices.contains(index) { proxy.scrollTo(presentation.values[index]) }
            }
        }
    }
}
