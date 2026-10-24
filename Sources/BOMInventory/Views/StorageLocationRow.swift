import SwiftUI

struct StorageLocationRow: View {
    var location: StorageLocation
    var selected: Bool
    var select: () -> Void
    var save: (String) throws -> Void
    var body: some View {
        DescriptionRow(name: location.displayName, description: location.description, selected: selected, kind: "storage", canEdit: location.name != nil, select: select, save: save)
    }
}
