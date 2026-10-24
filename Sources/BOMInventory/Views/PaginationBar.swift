import SwiftUI

struct PaginationBar: View {
    var count: Int
    @Binding var page: Int
    @Binding var pageSize: Int
    private var pages: Int { max(1, (count + pageSize - 1) / pageSize) }
    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) parts").foregroundStyle(Theme.yellow)
            Spacer()
            pageButton("chevron.left.2", label: "First page", disabled: page == 0) { page = 0 }
            pageButton("chevron.left", label: "Previous page", disabled: page == 0) { page -= 1 }
            Text("Page \(page + 1) of \(pages)").monospacedDigit()
            pageButton("chevron.right", label: "Next page", disabled: page >= pages - 1) { page += 1 }
            pageButton("chevron.right.2", label: "Last page", disabled: page >= pages - 1) { page = pages - 1 }
            Text(count == 0 ? "0 of 0" : "\(page * pageSize + 1)–\(min((page + 1) * pageSize, count)) of \(count)").foregroundStyle(Theme.muted).monospacedDigit()
            Picker("Rows", selection: $pageSize) { Text("25").tag(25); Text("50").tag(50); Text("100").tag(100) }.labelsHidden().frame(width: 65)
        }.padding(.horizontal, 12).frame(height: 38).background(Theme.raised)
    }
    private func pageButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).disabled(disabled).accessibilityLabel(label)
    }
}
