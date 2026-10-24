import Foundation

/// Deterministic component hints; does not infer from supplier part numbers or package sizes.
struct DescriptionAnalysis {
    static let builtInLabels = ["Inductor", "Capacitor", "Resistor", "Crystal", "Oscillator", "IC"]
    var value = ""
    var tolerance = ""
    var label = ""

    static func analyze(_ description: String, valueHint: String = "") -> DescriptionAnalysis {
        var result = DescriptionAnalysis()
        func match(_ pattern: String, in text: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<found.numberOfRanges).map { Range(found.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        func has(_ pattern: String) -> Bool { match(pattern, in: description) != nil }
        let number = #"(?:\d+(?:\.\d+)?|\.\d+)"#
        let boundary = #"(?<![\p{L}\p{N}.])"#
        let end = #"(?![\p{L}\p{N}])"#
        // Avoid milliohm/DCR measurements when an inductance or capacitance is present.
        func resistance(_ text: String) -> String {
            if let m = match(boundary + #"(\d+)([kKmM])(\d+)\s*(?:[oO][hH][mM][sS]?|[ΩΩ])"# + end, in: text) {
                return "\(m[1]).\(m[3])\(m[2].lowercased() == "k" ? "k" : m[2])Ω"
            }
            if let m = match(boundary + "(" + number + #")\s*([kKmM]?)\s*(?:[oO][hH][mM][sS]?|[ΩΩ])"# + end, in: text) {
                return m[1] + (m[2] == "K" ? "k" : m[2]) + "Ω"
            }
            return ""
        }
        func reactive(_ text: String, unit: String) -> String {
            guard let m = match(boundary + "(" + number + #")\s*([pPnNuUµμmM]?)"# + unit + end, in: text) else { return "" }
            let prefix = ["µ": "u", "μ": "u", "U": "u", "P": "p", "N": "n"][m[2]] ?? m[2]
            return m[1] + prefix + unit
        }
        func frequency(_ text: String) -> String {
            guard let m = match(boundary + "(" + number + #")\s*([kKMG]?)\s*[hH][zZ]"# + end, in: text) else { return "" }
            return m[1] + (m[2] == "K" ? "k" : m[2]) + "Hz"
        }
        let source = valueHint.isEmpty ? description : valueHint
        let inductance = reactive(source, unit: "H"), capacitance = reactive(source, unit: "F")
        let ohms = resistance(source), hz = frequency(source)
        if has(#"(?i)\bcrystal\b"#) { result.label = "Crystal"; result.value = hz }
        else if has(#"(?i)\boscillator\b"#) { result.label = "Oscillator"; result.value = hz }
        else if has(#"(?i)\binductor(?:s)?\b"#) { result.label = "Inductor"; result.value = inductance }
        else if has(#"(?i)\bcapacitor(?:s)?\b"#) { result.label = "Capacitor"; result.value = capacitance }
        else if has(#"(?i)\bresistor(?:s)?\b"#) { result.label = "Resistor"; result.value = ohms }
        else if !inductance.isEmpty { result.label = "Inductor"; result.value = inductance }
        else if !capacitance.isEmpty { result.label = "Capacitor"; result.value = capacitance }
        else if !ohms.isEmpty { result.label = "Resistor"; result.value = ohms }
        else if has(#"(?i)\bIC\b|\bintegrated\s+circuit\b"#) { result.label = "IC" }
        let sign = #"(?:±|\+\s*/\s*-)\s*("# + number + #")\s*"#
        // Percentage is component tolerance; ppm/°C is a temperature coefficient.
        if let m = match(sign + #"(%)"#, in: description) {
            result.tolerance = "±" + m[1] + "%"
        } else if let m = match(sign + #"((?i:ppm))(?![\p{L}\p{N}]|\s*/|\s*per\b)"#, in: description) {
            result.tolerance = "±" + m[1] + "ppm"
        }
        return result
    }
    func fillingMissing(in part: inout Part) {
        if part.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { part.value = value }
        if part.tolerance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { part.tolerance = tolerance }
        if !label.isEmpty && !part.labels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) { part.labels.append(label) }
    }
}
