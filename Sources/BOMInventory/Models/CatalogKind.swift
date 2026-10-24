import Foundation

enum CatalogKind { case project, storage
    var title: String { self == .project ? "Project" : "Storage" }
}
struct CatalogDraft: Identifiable {
    let id = UUID()
    var originalName: String?
    var name = ""
    var description = ""
}
