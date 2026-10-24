/// Independently ordered, persistent suggestions for editable part fields.
enum RecentField: String, CaseIterable {
    case manufacturer
    case package
    case storage

    func value(in part: Part) -> String {
        switch self {
        case .manufacturer: part.manufacturer
        case .package: part.package
        case .storage: part.storage
        }
    }
}
