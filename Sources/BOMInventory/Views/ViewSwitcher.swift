import SwiftUI

struct ViewSwitcher: View {
    @Binding var selection: InventorySection
    @State private var showingMenu = false
    var body: some View {
        Button { showingMenu.toggle() } label: {
            HStack {
                Text(selection.rawValue).fontWeight(.bold)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }.foregroundStyle(Theme.yellow).padding(.horizontal, 14)
                .frame(width: 150, height: 34).background(Theme.raised)
        }.buttonStyle(.plain).accessibilityLabel("View switcher: \(selection.rawValue)")
            .help("Switch between Parts, Storage, Projects, and Purchase")
            .popover(isPresented: $showingMenu, arrowEdge: .bottom) {
                VStack(spacing: 2) {
                    ForEach(InventorySection.allCases, id: \.self) { item in
                        Button {
                            selection = item
                            showingMenu = false
                        } label: {
                            HStack {
                                Text(item.rawValue).fontWeight(.semibold)
                                Spacer()
                                if item == selection { Image(systemName: "checkmark") }
                            }.padding(.horizontal, 12).frame(width: 160, height: 32)
                                .foregroundStyle(Theme.yellow)
                                .background(item == selection ? Theme.selection : Color.clear)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(5).background(Theme.raised)
            }
    }
}
