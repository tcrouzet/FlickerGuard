import Testing
import CoreGraphics
import Synchronization
@testable import FlickerGuard

private func dimmingDiagnostic(
    level: Float? = 1, hasOriginal: Bool = true, uuid: String? = "test-panel",
    macModel: String? = "Mac17,13", builtin: Bool = true
) throws -> DisplayDiagnostic {
    let panel = DisplayIdentity(
        displayID: 1, isBuiltin: builtin, macModel: macModel, manufacturer: "APP",
        modelName: "Test panel", vendorID: 0x0610, productID: 0xA068, hardwareID: uuid, edid: nil
    )
    let table = try TransferTable(red: [0, 0.4, 1], green: [0, 0.5, 1], blue: [0, 0.6, 1])
    let hardware: Result<HardwareBrightness, Error>? = try level.map { .success(try HardwareBrightness(level: $0)) }
    return DisplayDiagnostic(
        display: panel, isRecognizedOLED: true, transferTable: hasOriginal ? table : nil,
        hardwareBrightness: hardware, errorMessage: nil
    )
}

@Test func softwareCurvePreservesCalibrationAndRestoresExactlyAtFullLevel() throws {
    let original = try TransferTable(red: [0, 0.4, 1], green: [0, 0.6, 1], blue: [0, 0.8, 1])
    let half = try BrightnessCurve.table(from: original, level: 0.5)
    #expect(half.red == [0, 0.2, 0.5])
    #expect(half.green == [0, 0.3, 0.5])
    #expect(half.blue == [0, 0.4, 0.5])
    #expect(try BrightnessCurve.table(from: original, level: 1) == original)
    #expect(try BrightnessCurve.table(from: original, level: 0.1).red.last == 0.1)
}

@Test func successiveSoftwareLevelsUseTheOriginalTable() throws {
    let original = try TransferTable(red: [0, 1], green: [0, 1], blue: [0, 1])
    let first = try BrightnessCurve.table(from: original, level: 0.5)
    let second = try BrightnessCurve.table(from: original, level: 0.8)
    #expect(first.red == [0, 0.5])
    #expect(second.red == [0, 0.8])
    #expect(original.red == [0, 1])
}

@Test func softwareCurveRejectsUnsafeAndNonFiniteLevels() throws {
    let original = try TransferTable(red: [0, 1], green: [0, 1], blue: [0, 1])
    for level: Double in [.nan, .infinity, -.infinity, -1, 0, 0.009, 1.001] {
        #expect(throws: DimmingError.self) { try BrightnessCurve.table(from: original, level: level) }
    }
}

@Test func readbackVerificationRequiresEveryChannelAndTableSize() throws {
    let expected = try TransferTable(red: [0, 0.5], green: [0, 0.5], blue: [0, 0.5])
    #expect(BrightnessCurve.matches(expected, expected))
    let quantized = try TransferTable(red: [0, 0.5005], green: [0, 0.5], blue: [0, 0.5])
    #expect(BrightnessCurve.matches(quantized, expected))
    for actual in [
        try TransferTable(red: [0, 0.6], green: [0, 0.5], blue: [0, 0.5]),
        try TransferTable(red: [0, 0.5], green: [0, 0.6], blue: [0, 0.5]),
        try TransferTable(red: [0, 0.5], green: [0, 0.5], blue: [0, 0.6]),
        try TransferTable(red: [0, 0.25, 0.5], green: [0, 0.25, 0.5], blue: [0, 0.25, 0.5])
    ] {
        #expect(!BrightnessCurve.matches(actual, expected))
    }
}

@Test func activationSetsMaximumAndMonitoringRequiresRawHardwareMaximum() throws {
    #expect(try DimmingEligibility.validate(dimmingDiagnostic()).displayID == 1)
    for level: Float in [0, 0.8, 0.995, 0.99999] {
        let diagnostic = try dimmingDiagnostic(level: level)
        #expect(try DimmingEligibility.validate(diagnostic).displayID == 1)
        let control = try TestDisplayControl()
        control.state.withLock { $0.brightness = level }
        let controller = DisplayTransferController(control: control)
        try controller.prepare(diagnostic)
        #expect(control.state.withLock { $0.brightness } == 1)
        control.state.withLock { $0.brightness = level }
        #expect(throws: DimmingError.self) { try controller.checkHardwareBrightness() }
        try controller.restore()
        #expect(control.state.withLock { $0.brightness } == level)
    }
}

@Test func activationRefusesUnknownPanelIdentityAndExternalDisplays() throws {
    for diagnostic in [
        try dimmingDiagnostic(uuid: nil), try dimmingDiagnostic(uuid: ""),
        try dimmingDiagnostic(macModel: nil), try dimmingDiagnostic(macModel: "Mac17,9"),
        try dimmingDiagnostic(builtin: false)
    ] {
        #expect(throws: DimmingError.self) { try DimmingEligibility.validate(diagnostic) }
    }
}

@Test func activationRequiresBothOriginalTableAndHardwareReading() throws {
    let missingTable = try dimmingDiagnostic(hasOriginal: false)
    #expect(throws: DimmingError.self) { try DimmingEligibility.validate(missingTable) }
    let missingHardware = try dimmingDiagnostic(level: nil)
    #expect(throws: HardwareBrightnessError.self) { try DimmingEligibility.validate(missingHardware) }
}

@Test func inactiveControllerCannotApplyAndRestorationIsANoop() throws {
    let controller = DisplayTransferController()
    #expect(!controller.needsRestoration)
    #expect(throws: DimmingError.self) { try controller.apply(level: 0.5) }
    #expect(throws: DimmingError.self) { try controller.checkHardwareBrightness() }
    try controller.restore()
    #expect(!controller.needsRestoration)
    #expect(controller.restoreBeforeReconfiguration(displayID: 1) == nil)
}

@Test func unverifiedActivationLeavesTheControllerUnmodified() throws {
    let controller = DisplayTransferController()
    let diagnostic = try dimmingDiagnostic(macModel: "Unknown Mac")
    #expect(throws: DimmingError.self) { try controller.prepare(diagnostic) }
    #expect(!controller.needsRestoration)
}

private final class TestDisplayControl: DisplayControl {
    enum Fault: Error, Sendable {
        case none, automaticRead, automaticWrite, brightnessWrite, tableWrite
        case ignoreAutomatic, ignoreBrightness, ignoreTable
    }

    enum Write: Equatable, Sendable {
        case table, brightness(Float), automatic(Bool)
    }

    struct State: Sendable {
        var table: TransferTable
        var brightness: Float = 0.42
        var automatic = true
        var mode: Int32 = 7
        var fault = Fault.none
        var writes: [Write] = []
    }

    let state: Mutex<State>

    init() throws {
        state = Mutex(State(table: try TransferTable(red: [0, 1], green: [0, 0.9], blue: [0, 0.8])))
    }

    func modeID(for display: DisplayIdentity) throws -> Int32 { state.withLock { $0.mode } }
    func readTable(_ displayID: CGDirectDisplayID) throws -> TransferTable { state.withLock { $0.table } }
    func writeTable(_ table: TransferTable, to displayID: CGDirectDisplayID) throws {
        try state.withLock {
            if $0.fault == .tableWrite { throw Fault.tableWrite }
            $0.writes.append(.table)
            if $0.fault != .ignoreTable { $0.table = table }
        }
    }
    func brightness(_ displayID: CGDirectDisplayID) throws -> HardwareBrightness {
        try state.withLock { try HardwareBrightness(level: $0.brightness) }
    }
    func setBrightness(_ level: Float, on displayID: CGDirectDisplayID) throws {
        try state.withLock {
            if $0.fault == .brightnessWrite { throw Fault.brightnessWrite }
            $0.writes.append(.brightness(level))
            if $0.fault != .ignoreBrightness { $0.brightness = level }
        }
    }
    func automaticBrightness(_ displayID: CGDirectDisplayID) throws -> Bool {
        try state.withLock {
            if $0.fault == .automaticRead { throw Fault.automaticRead }
            return $0.automatic
        }
    }
    func setAutomaticBrightness(_ enabled: Bool, on displayID: CGDirectDisplayID) throws {
        try state.withLock {
            if $0.fault == .automaticWrite { throw Fault.automaticWrite }
            $0.writes.append(.automatic(enabled))
            if $0.fault != .ignoreAutomatic { $0.automatic = enabled }
        }
    }
}

@Test(arguments: ["Mac17,13", "Mac17,11", "Mac17,12", "Mac17,10"])
func activationAndDeactivationRestoreHardwareAutomationAndOriginalTable(macModel: String) throws {
    for originalAutomatic in [true, false] {
        let control = try TestDisplayControl()
        control.state.withLock { $0.automatic = originalAutomatic }
        let original = control.state.withLock { $0.table }
        let controller = DisplayTransferController(control: control)
        for _ in 0..<2 {
            control.state.withLock { $0.writes = [] }
            try controller.prepare(dimmingDiagnostic(level: 0.42, macModel: macModel), level: 0.63)
            #expect(controller.needsRestoration)
            #expect(control.state.withLock { $0.writes } == [.table, .automatic(false), .table, .brightness(1)])
            #expect(control.state.withLock { $0.table } == (try BrightnessCurve.table(from: original, level: 0.63)))
            #expect(try controller.checkHardwareBrightness().level == 1)
            try controller.apply(level: 1)
            #expect(control.state.withLock { $0.table } == original)
            #expect(controller.needsRestoration)
            try controller.apply(level: 0.63)
            control.state.withLock { $0.writes = [] }
            try controller.restore()
            #expect(control.state.withLock { $0.writes } == [.table, .brightness(0.42), .automatic(originalAutomatic)])
            #expect(control.state.withLock { $0.brightness } == 0.42)
            #expect(control.state.withLock { $0.automatic } == originalAutomatic)
            #expect(control.state.withLock { $0.table } == original)
            #expect(!controller.needsRestoration)
        }
    }
}

@Test func failedActivationRetainsRecoveryAndRejectsUnverifiedWrites() throws {
    for fault: TestDisplayControl.Fault in [.automaticRead, .automaticWrite, .brightnessWrite, .tableWrite, .ignoreAutomatic, .ignoreBrightness, .ignoreTable] {
        let control = try TestDisplayControl()
        let original = control.state.withLock { $0.table }
        let controller = DisplayTransferController(control: control)
        control.state.withLock { $0.fault = fault }
        #expect(throws: (any Error).self) { try controller.prepare(dimmingDiagnostic(), level: 0.5) }
        #expect(controller.needsRestoration == (fault != .automaticRead))
        if fault == .automaticRead { #expect(control.state.withLock { $0.writes.isEmpty }) }
        control.state.withLock { $0.fault = .none }
        try controller.restore()
        #expect(!controller.needsRestoration)
        #expect(control.state.withLock { $0.brightness } == 0.42)
        #expect(control.state.withLock { $0.automatic })
        #expect(control.state.withLock { $0.table } == original)
    }
}

@Test func failedRestorationKeepsTheSnapshotForRetryAtEveryStage() throws {
    for fault: TestDisplayControl.Fault in [.tableWrite, .brightnessWrite, .automaticWrite, .ignoreBrightness, .ignoreAutomatic] {
        let control = try TestDisplayControl()
        let original = control.state.withLock { $0.table }
        let controller = DisplayTransferController(control: control)
        try controller.prepare(dimmingDiagnostic(), level: 0.5)
        control.state.withLock { $0.fault = fault }
        #expect(throws: (any Error).self) { try controller.restore() }
        #expect(controller.needsRestoration)
        #expect(throws: DimmingError.self) { try controller.prepare(dimmingDiagnostic()) }
        control.state.withLock { $0.fault = .none }
        try controller.restore()
        #expect(!controller.needsRestoration)
        #expect(control.state.withLock { $0.brightness } == 0.42)
        #expect(control.state.withLock { $0.automatic })
        #expect(control.state.withLock { $0.table } == original)
    }
}

@Test func reconfigurationRestoresTableBeforeModeChangeAndSettingsAfterwards() throws {
    let control = try TestDisplayControl()
    let original = control.state.withLock { $0.table }
    let controller = DisplayTransferController(control: control)
    try controller.prepare(dimmingDiagnostic(), level: 0.5)
    #expect(controller.restoreBeforeReconfiguration(displayID: 999) == nil)
    let result = try #require(controller.restoreBeforeReconfiguration(displayID: 1))
    try result.get()
    #expect(control.state.withLock { $0.table } == original)
    #expect(controller.needsRestoration)
    #expect(throws: DimmingError.self) { try controller.apply(level: 0.5) }
    #expect(throws: DimmingError.self) { try controller.checkHardwareBrightness() }
    control.state.withLock { $0.mode = 8; $0.writes = [] }
    let repeated = try #require(controller.restoreBeforeReconfiguration(displayID: 1))
    try repeated.get()
    #expect(control.state.withLock { $0.writes.isEmpty })
    try controller.restore()
    #expect(control.state.withLock { $0.writes } == [.brightness(0.42), .automatic(true)])
    #expect(!controller.needsRestoration)
}

@Test func externalChangesToNativeAutomationStopDimming() throws {
    let control = try TestDisplayControl()
    let controller = DisplayTransferController(control: control)
    try controller.prepare(dimmingDiagnostic(), level: 0.5)
    control.state.withLock { $0.automatic = true }
    #expect(throws: HardwareBrightnessError.self) { try controller.checkHardwareBrightness() }
    #expect(throws: HardwareBrightnessError.self) { try controller.apply(level: 0.4) }
    try controller.restore()
    #expect(!controller.needsRestoration)
}

@Test func externallyReplacedSoftwareTableIsRepairedOnlyWhenDifferent() throws {
    let control = try TestDisplayControl()
    let baseline = control.state.withLock { $0.table }
    let controller = DisplayTransferController(control: control)
    try controller.prepare(dimmingDiagnostic(), level: 0.2)
    control.state.withLock { $0.writes = [] }
    #expect(try !controller.ensureSoftwareLevel(0.2))
    #expect(control.state.withLock { $0.writes.isEmpty })
    control.state.withLock { $0.table = baseline }
    #expect(try controller.ensureSoftwareLevel(0.2))
    #expect(control.state.withLock { $0.table } == (try BrightnessCurve.table(from: baseline, level: 0.2)))
    #expect(control.state.withLock { $0.writes } == [.table])
    #expect(try !controller.ensureSoftwareLevel(0.2))
    #expect(control.state.withLock { $0.writes } == [.table])
    try controller.restore()
    #expect(control.state.withLock { $0.table } == baseline)
}

@Test func softwareTableRepairStillRequiresHardwareMaximumAndValidBackup() throws {
    let control = try TestDisplayControl()
    let controller = DisplayTransferController(control: control)
    #expect(throws: DimmingError.self) { try controller.ensureSoftwareLevel(0.2) }
    try controller.prepare(dimmingDiagnostic(), level: 0.2)
    control.state.withLock { $0.brightness = 0.5; $0.writes = [] }
    #expect(throws: DimmingError.self) { try controller.ensureSoftwareLevel(0.2) }
    #expect(control.state.withLock { $0.writes.isEmpty })
    control.state.withLock { $0.brightness = 1 }
    try #require(controller.restoreBeforeReconfiguration(displayID: 1)).get()
    #expect(controller.isReconfiguring)
    #expect(throws: DimmingError.self) { try controller.ensureSoftwareLevel(0.2) }
    try controller.restore()
    #expect(!controller.isReconfiguring)
}
