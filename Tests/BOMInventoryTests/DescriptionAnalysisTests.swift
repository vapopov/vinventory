import XCTest
@testable import BOMInventory

final class DescriptionAnalysisTests: XCTestCase {
    func testResistanceSpellingsAndTolerance() {
        for (raw, expected) in [("4.7kΩ", "4.7kΩ"), ("4.7kOhm", "4.7kΩ"), ("4k7Ohm", "4.7kΩ"), ("4k7Ω", "4.7kΩ"), ("4MOhm", "4MΩ")] {
            let result = DescriptionAnalysis.analyze("\(raw) ±1% 62.5mW 0402 Thick Film Resistor")
            XCTAssertEqual(result.value, expected)
            XCTAssertEqual(result.tolerance, "±1%")
            XCTAssertEqual(result.label, "Resistor")
        }
    }
    func testTemperatureCoefficientIsNotComponentTolerance() {
        XCTAssertEqual(DescriptionAnalysis.analyze("200kΩ 62.5mW Thick Film Resistor ±100ppm/℃ ±1%").tolerance, "±1%")
        XCTAssertEqual(DescriptionAnalysis.analyze("24kΩ ±100ppm/℃ Resistor").tolerance, "")
    }
    func testCrystalFrequencyTakesPriorityOverLoadCapacitance() {
        let result = DescriptionAnalysis.analyze("Crystal 40MHz ±10ppm 10pF SMD3225-4P")
        XCTAssertEqual(result.value, "40MHz")
        XCTAssertEqual(result.tolerance, "±10ppm")
        XCTAssertEqual(result.label, "Crystal")
    }
    func testCapacitanceInductanceAndOscillator() {
        for unit in ["pF", "nF", "uF", "µF"] {
            let result = DescriptionAnalysis.analyze("15\(unit) ±1% 50V Ceramic Capacitor C0G 0402")
            XCTAssertEqual(result.value, "15" + (unit == "µF" ? "uF" : unit))
            XCTAssertEqual(result.label, "Capacitor")
            XCTAssertEqual(result.tolerance, "±1%")
        }
        for unit in ["uH", "nH", "pH"] {
            let result = DescriptionAnalysis.analyze("1.7A 2.2\(unit) ±20% 140mΩ 0806 Fixed Inductors")
            XCTAssertEqual(result.value, "2.2\(unit)")
            XCTAssertEqual(result.label, "Inductor")
        }
        XCTAssertEqual(DescriptionAnalysis.analyze("Oscillator 25MHz +/-50ppm").label, "Oscillator")
        XCTAssertEqual(DescriptionAnalysis.analyze("IC RF WiFi 2400MHz QFN-24").label, "IC")
        for (unit, label) in [("4.7kΩ", "Resistor"), ("15pF", "Capacitor"), ("100nH", "Inductor")] {
            XCTAssertEqual(DescriptionAnalysis.analyze(unit).label, label)
        }
        XCTAssertEqual(DescriptionAnalysis.analyze("0402 50V 62.5mW").value, "")
        XCTAssertEqual(DescriptionAnalysis.analyze("0402 50V 62.5mW").label, "")
    }
    func testImportDetectionManualOverridesAndIgnoredColumns() throws {
        var document = try BOMImport(text: "Part Number,Description,Unit Price\nA,15pF ±1% 50V Ceramic Capacitor,0.42", filename: "x")
        let value = try XCTUnwrap(document.headers.firstIndex(of: "Value"))
        let tolerance = try XCTUnwrap(document.headers.firstIndex(of: "Tolerance"))
        let labels = try XCTUnwrap(document.headers.firstIndex(of: "Labels"))
        XCTAssertEqual(document.rows[0].values[value], "15pF")
        XCTAssertEqual(document.rows[0].values[tolerance], "±1%")
        XCTAssertEqual(document.rows[0].values[labels], "Capacitor")
        document.setValue("22nF ±5% Capacitor", row: 0, column: 1)
        XCTAssertEqual(document.rows[0].values[value], "22nF")
        XCTAssertEqual(document.rows[0].values[tolerance], "±5%")
        document.setValue("33nF", row: 0, column: value)
        document.setValue("1uF ±10% Capacitor", row: 0, column: 1)
        XCTAssertEqual(document.rows[0].values[value], "33nF", "Manual values survive description edits")
        XCTAssertEqual(document.rows[0].values[tolerance], "±10%")
        document.ignoredCustomColumns.insert(2)
        XCTAssertNil(try document.selectedParts()[0].customFields["Unit Price"])
        document.ignoredCustomColumns.remove(2)
        XCTAssertEqual(try document.selectedParts()[0].customFields["Unit Price"], "0.42")
    }
    func testExplicitCSVFieldsTakePriority() throws {
        let document = try BOMImport(text: "Part Number,Description,Value,Tolerance,Labels\nA,15pF ±1% Capacitor,22nF,5%,Manual", filename: "x")
        let part = try XCTUnwrap(document.selectedParts().first)
        XCTAssertEqual(part.value, "22nF")
        XCTAssertEqual(part.tolerance, "5%")
        XCTAssertEqual(part.labels, ["Manual"])
    }
    @MainActor func testBuiltInLabelsRemainAfterUnassignmentAndRestart() throws {
        let repository = try SQLiteRepository(path: ":memory:")
        let store = InventoryStore(repository: repository)
        XCTAssertEqual(Set(store.labels), Set(DescriptionAnalysis.builtInLabels))
        var part = Part(); part.number = "A"; part.labels = ["Inductor", "Temporary"]
        try store.save(part)
        try store.delete(part)
        XCTAssertEqual(Set(store.labels), Set(DescriptionAnalysis.builtInLabels))
        XCTAssertFalse(store.labels.contains("Temporary"))
    }
}
