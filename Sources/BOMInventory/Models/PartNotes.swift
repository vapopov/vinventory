import Foundation

struct PartNotes: Codable, Equatable {
    var text = ""
    var rtf = Data()
    /// RTFD attachment filenames mapped to managed local files.
    var images: [String: String] = [:]
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty }
}
