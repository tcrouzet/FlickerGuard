import Foundation
import Testing
@testable import FlickerGuard

private func display(
    builtin: Bool = true, vendor: UInt32 = 1234, product: UInt32 = 5678,
    manufacturer: String? = "Test manufacturer", model: String? = "Test panel",
    macModel: String? = "Test Mac"
) -> DisplayIdentity {
    DisplayIdentity(
        displayID: 1, isBuiltin: builtin, macModel: macModel, manufacturer: manufacturer,
        modelName: model, vendorID: vendor, productID: product,
        hardwareID: nil, edid: nil
    )
}

private let signature = OLEDDisplaySignature(
    macModel: "Test Mac",
    manufacturer: "Test manufacturer", modelName: "Test panel", vendorID: 1234, productID: 5678
)

@Test func exactSignatureRequiresEverySpecifiedProperty() {
    #expect(signature.matches(display()))
    #expect(!signature.matches(display(vendor: 9999)))
    #expect(!signature.matches(display(product: 9999)))
    #expect(!signature.matches(display(manufacturer: "Other manufacturer")))
    #expect(!signature.matches(display(model: "Other panel")))
    #expect(!signature.matches(display(manufacturer: nil)))
    #expect(!signature.matches(display(model: nil)))
    #expect(!signature.matches(display(macModel: "Other Mac")))
    #expect(!signature.matches(display(macModel: nil)))
}

@Test func externalAndUnknownPanelsAreRefused() {
    #expect(!signature.matches(display(builtin: false)))
    for (vendor, product) in [(UInt32(0), UInt32(5678)), (1234, 0), (0x756E6B6E, 5678), (1234, 0x717)] {
        let unknown = OLEDDisplaySignature(macModel: "Test Mac", manufacturer: nil, modelName: nil, vendorID: vendor, productID: product)
        #expect(!unknown.matches(display(vendor: vendor, product: product)))
    }
    #expect(!OLEDSignatureDatabase.recognizes(display(model: "Retina PROLED XDR Pro HDR")))
    #expect(!OLEDSignatureDatabase.recognizes(display()))
}

@Test func numericSignatureStillRequiresExactHardwareIDs() {
    let numeric = OLEDDisplaySignature(macModel: "Test Mac", manufacturer: nil, modelName: nil, vendorID: 1234, productID: 5678)
    #expect(numeric.matches(display(manufacturer: nil, model: nil)))
    #expect(!numeric.matches(display(product: 9999)))
    #expect(!numeric.matches(display(builtin: false)))
}

@Test func reportedInternalOLEDPanelIsRecognized() {
    let panel = display(
        vendor: 0x0610, product: 0xA068, manufacturer: "APP",
        model: "Built-in Retina Display", macModel: "Mac17,13"
    )
    #expect(OLEDSignatureDatabase.recognizes(panel))
    let diagnostic = DisplayDiagnostic(display: panel, isRecognizedOLED: OLEDSignatureDatabase.recognizes(panel), transferTable: nil, hardwareBrightness: nil, errorMessage: nil)
    #expect(diagnostic.status == tr("diag.oledRecognized"))
    #expect(diagnostic.report.contains(tr("diag.macModel", ["value": "Mac17,13"])))
}

@Test(arguments: ["Mac17,10", "Mac17,11", "Mac17,12"])
func additionalPROLEDModelsRecognizeInternalApplePanels(macModel: String) {
    for product: UInt32 in [1234, 5678] {
        #expect(OLEDSignatureDatabase.recognizes(display(
            vendor: 0x0610, product: product, manufacturer: "APP", macModel: macModel
        )))
    }
}

@Test(arguments: ["Mac17,10", "Mac17,11", "Mac17,12"])
func additionalPROLEDModelsStillRequireValidInternalApplePanels(macModel: String) {
    #expect(!OLEDSignatureDatabase.recognizes(display(builtin: false, vendor: 0x0610, manufacturer: "APP", macModel: macModel)))
    #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0611, manufacturer: "APP", macModel: macModel)))
    for manufacturer: String? in [nil, "Other manufacturer"] {
        #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0610, manufacturer: manufacturer, macModel: macModel)))
    }
    for product: UInt32 in [0, 0x717] {
        #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0610, product: product, manufacturer: "APP", macModel: macModel)))
    }
}

@Test func reportedPanelIDsRequireTheVerifiedMacAndInternalDisplay() {
    #expect(!OLEDSignatureDatabase.recognizes(display(builtin: false, vendor: 0x0610, product: 0xA068, manufacturer: "APP", macModel: "Mac17,13")))
    for macModel: String? in [nil, "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9", "Mac17,14", "Unknown Mac"] {
        #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0610, product: 0xA068, manufacturer: "APP", macModel: macModel)))
    }
    #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0610, product: 0xA067, manufacturer: "APP", macModel: "Mac17,13")))
    #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0611, product: 0xA068, manufacturer: "APP", macModel: "Mac17,13")))
    #expect(!OLEDSignatureDatabase.recognizes(display(vendor: 0x0610, product: 0xA068, manufacturer: nil, macModel: "Mac17,13")))
}

@Test func transferTablePreservesAllChannels() throws {
    let table = try TransferTable(red: [0, 0.4, 1], green: [0, 0.5, 1], blue: [0, 0.6, 1])
    #expect(table.red == [0, 0.4, 1])
    #expect(table.green == [0, 0.5, 1])
    #expect(table.blue == [0, 0.6, 1])
}

@Test func invalidTransferTablesAreRefused() {
    #expect(throws: DisplayReadError.self) { try TransferTable(red: [], green: [], blue: []) }
    #expect(throws: DisplayReadError.self) { try TransferTable(red: [0, 1], green: [0], blue: [0, 1]) }
    for invalid: Float in [.nan, .infinity, -.infinity, -0.1, 1.1] {
        #expect(throws: DisplayReadError.self) {
            try TransferTable(red: [0, invalid], green: [0, 1], blue: [0, 1])
        }
        #expect(throws: DisplayReadError.self) {
            try TransferTable(red: [0, 1], green: [0, invalid], blue: [0, 1])
        }
        #expect(throws: DisplayReadError.self) {
            try TransferTable(red: [0, 1], green: [0, 1], blue: [0, invalid])
        }
    }
}

@Test @MainActor func manufacturerCodesRejectUnknownValues() {
    #expect(InternalDisplayDetector.manufacturerCode(0x0610) == "APP")
    for invalid: UInt32 in [0, 1, 0x7FFF, 0x8000, .max] {
        #expect(InternalDisplayDetector.manufacturerCode(invalid) == nil)
    }
}

@Test func detectedPanelWithUnverifiedSignatureIsReportedAsDetected() {
    let diagnostic = DisplayDiagnostic(
        display: display(), isRecognizedOLED: false, transferTable: nil, hardwareBrightness: nil, errorMessage: nil
    )
    #expect(diagnostic.status == tr("diag.oledUnverified"))
    #expect(!diagnostic.report.contains(tr("diag.emptyDatabase")))
    #expect(diagnostic.report.contains(tr("diag.signature", ["value": tr("diag.unverified")])))
}

@Test func inaccessiblePanelIsReportedAsAnIdentificationFailure() {
    let diagnostic = DisplayDiagnostic(
        display: nil, isRecognizedOLED: false, transferTable: nil, hardwareBrightness: nil,
        errorMessage: "Énumération indisponible"
    )
    #expect(diagnostic.status == tr("diag.noDisplay"))
    #expect(diagnostic.report.contains(tr("diag.error", ["error": "Énumération indisponible"])))
    #expect(diagnostic.report.contains(tr("diag.hardwareNotRead")))
}

@Test @MainActor func attenuationStartsInactiveUntilUserActivation() {
    let state = AppState()
    #expect(!state.isActive)
    #expect(state.softwareLevel == 1)
    #expect(!state.needsRestoration)
}

@Test @MainActor func localReadOnlyDiagnostic() {
    print("Modèle du Mac lu via IOKit : \(InternalDisplayDetector.macModel() ?? "Indisponible")")
    let diagnostic = DisplayDiagnostic.capture()
    print(diagnostic.report)
    if let panel = diagnostic.display {
        #expect(panel.isBuiltin)
        #expect(diagnostic.transferTable != nil || diagnostic.errorMessage != nil)
    } else {
        #expect(!diagnostic.isRecognizedOLED)
        #expect(diagnostic.transferTable == nil)
        #expect(diagnostic.errorMessage != nil)
    }
    if diagnostic.isRecognizedOLED {
        #expect(diagnostic.status == tr("diag.oledRecognized"))
    } else {
        #expect(diagnostic.status == (diagnostic.display == nil ? tr("diag.noDisplay") : tr("diag.oledUnverified")))
    }
}

@Test func hardwareBrightnessReportsTheNormalizedLevelAsAPercentage() throws {
    for (level, percentage): (Float, Int) in [(0, 0), (0.375, 38), (0.8, 80), (1, 100)] {
        let brightness = try HardwareBrightness(level: level)
        #expect(brightness.level == level)
        #expect(brightness.percentage == percentage)
        let diagnostic = DisplayDiagnostic(
            display: display(), isRecognizedOLED: false, transferTable: nil,
            hardwareBrightness: .success(brightness), errorMessage: nil
        )
        #expect(diagnostic.report.contains(tr("diag.hardware", ["level": brightness.level.formatted(.percent.precision(.fractionLength(0)))])))
    }
}

@Test func hardwareBrightnessRejectsInvalidLevels() {
    for level: Float in [.nan, .infinity, -.infinity, -0.1, 1.1] {
        #expect(throws: HardwareBrightnessError.self) { try HardwareBrightness(level: level) }
    }
}

@Test func hardwareBrightnessFailurePreservesTheOtherDiagnostics() throws {
    let table = try TransferTable(red: [0, 1], green: [0, 1], blue: [0, 1])
    let diagnostic = DisplayDiagnostic(
        display: display(), isRecognizedOLED: true, transferTable: table,
        hardwareBrightness: .failure(HardwareBrightnessError.readFailed(1000)), errorMessage: nil
    )
    #expect(diagnostic.report.contains(tr("diag.hardwareError", ["error": tr("error.hardwareRead", ["code": "1000"])])))
    #expect(diagnostic.report.contains(tr("diag.table", ["count": 2.formatted()])))
    #expect(diagnostic.status == tr("diag.oledRecognized"))
}

@Test func hardwareBrightnessReaderRefusesAnInvalidDisplay() {
    #expect(throws: DisplayReadError.self) { try HardwareBrightnessReader.read(displayID: 0) }
    #expect(throws: DisplayReadError.self) { try HardwareBrightnessReader.set(0.5, displayID: 0) }
    #expect(throws: DisplayReadError.self) { try HardwareBrightnessReader.automaticBrightness(displayID: 0) }
    #expect(throws: DisplayReadError.self) { try HardwareBrightnessReader.setAutomaticBrightness(false, displayID: 0) }
    #expect(throws: HardwareBrightnessError.self) { try HardwareBrightnessReader.set(.nan, displayID: 0) }
}
