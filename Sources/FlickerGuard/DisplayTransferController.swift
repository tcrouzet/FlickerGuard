import ColorSync
import CoreGraphics
import Foundation
import Synchronization

enum DimmingError: LocalizedError {
    case incompatibleDisplay
    case missingIdentity
    case hardwareNotMaximum
    case originalUnavailable
    case restorationRequired
    case inactive
    case invalidLevel
    case displayChanged
    case transferWrite(Int32)
    case verificationFailed
    case configurationObserver(Int32)

    var errorDescription: String? {
        switch self {
        case .incompatibleDisplay: tr("error.incompatibleDisplay")
        case .missingIdentity: tr("error.missingIdentity")
        case .hardwareNotMaximum: tr("error.hardwareMaximum")
        case .originalUnavailable: tr("error.originalUnavailable")
        case .restorationRequired: tr("error.restorationRequired")
        case .inactive: tr("error.inactive")
        case .invalidLevel: tr("error.invalidSoftwareLevel")
        case .displayChanged: tr("error.displayChanged")
        case .transferWrite(let code): tr("error.transferWrite", ["code": String(code)])
        case .verificationFailed: tr("error.verification")
        case .configurationObserver(let code): tr("error.observer", ["code": String(code)])
        }
    }
}

enum DimmingEligibility {
    static func validate(_ diagnostic: DisplayDiagnostic) throws -> DisplayIdentity {
        guard let display = diagnostic.display, OLEDSignatureDatabase.recognizes(display) else {
            throw DimmingError.incompatibleDisplay
        }
        guard let uuid = display.hardwareID, !uuid.isEmpty else { throw DimmingError.missingIdentity }
        guard diagnostic.transferTable != nil else { throw DimmingError.originalUnavailable }
        guard let reading = diagnostic.hardwareBrightness else { throw HardwareBrightnessError.unavailableAPI }
        _ = try reading.get()
        return display
    }
}

enum BrightnessCurve {
    static func table(from original: TransferTable, level: Double) throws -> TransferTable {
        guard level.isFinite, (0.1...1).contains(level) else { throw DimmingError.invalidLevel }
        let factor = Float(level)
        return try TransferTable(
            red: original.red.map { $0 * factor },
            green: original.green.map { $0 * factor },
            blue: original.blue.map { $0 * factor }
        )
    }

    static func matches(_ actual: TransferTable, _ expected: TransferTable) -> Bool {
        guard actual.red.count == expected.red.count else { return false }
        return zip(
            [actual.red, actual.green, actual.blue],
            [expected.red, expected.green, expected.blue]
        ).allSatisfy { actual, expected in
            zip(actual, expected).allSatisfy { abs($0 - $1) <= 0.001 }
        }
    }
}

private struct OriginalTransferStore: Sendable {
    let display: DisplayIdentity
    let modeID: Int32
    let table: TransferTable
    let brightness: Float
    let automaticBrightness: Bool
    var tableRestored = false
}

protocol DisplayControl: Sendable {
    func modeID(for display: DisplayIdentity) throws -> Int32
    func readTable(_ displayID: CGDirectDisplayID) throws -> TransferTable
    func writeTable(_ table: TransferTable, to displayID: CGDirectDisplayID) throws
    func brightness(_ displayID: CGDirectDisplayID) throws -> HardwareBrightness
    func setBrightness(_ level: Float, on displayID: CGDirectDisplayID) throws
    func automaticBrightness(_ displayID: CGDirectDisplayID) throws -> Bool
    func setAutomaticBrightness(_ enabled: Bool, on displayID: CGDirectDisplayID) throws
}

struct SystemDisplayControl: DisplayControl {
    func modeID(for display: DisplayIdentity) throws -> Int32 {
        guard display.displayID != kCGNullDirectDisplay,
              OLEDSignatureDatabase.recognizes(display),
              CGDisplayIsBuiltin(display.displayID) != 0,
              CGDisplayIsActive(display.displayID) != 0,
              CGDisplayVendorNumber(display.displayID) == display.vendorID,
              CGDisplayModelNumber(display.displayID) == display.productID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(display.displayID)?.takeRetainedValue(),
              let expectedUUID = display.hardwareID, !expectedUUID.isEmpty,
              CFUUIDCreateString(nil, uuid) as String == expectedUUID,
              let mode = CGDisplayCopyDisplayMode(display.displayID) else { throw DimmingError.displayChanged }
        return mode.ioDisplayModeID
    }

    func readTable(_ displayID: CGDirectDisplayID) throws -> TransferTable { try DisplayTransferReader.read(displayID: displayID) }

    func writeTable(_ table: TransferTable, to displayID: CGDirectDisplayID) throws {
        let result = CGSetDisplayTransferByTable(displayID, UInt32(table.red.count), table.red, table.green, table.blue)
        guard result == .success else { throw DimmingError.transferWrite(result.rawValue) }
    }

    func brightness(_ displayID: CGDirectDisplayID) throws -> HardwareBrightness { try HardwareBrightnessReader.read(displayID: displayID) }
    func setBrightness(_ level: Float, on displayID: CGDirectDisplayID) throws { try HardwareBrightnessReader.set(level, displayID: displayID) }
    func automaticBrightness(_ displayID: CGDirectDisplayID) throws -> Bool { try HardwareBrightnessReader.automaticBrightness(displayID: displayID) }
    func setAutomaticBrightness(_ enabled: Bool, on displayID: CGDirectDisplayID) throws {
        try HardwareBrightnessReader.setAutomaticBrightness(enabled, displayID: displayID)
    }
}

final class DisplayTransferController: Sendable {
    // CoreGraphics can request restoration from its event thread before a mode change.
    // shortcut: the backup lives in memory; add a recovery store if crash recovery is required.
    private let original = Mutex<OriginalTransferStore?>(nil)
    private let control: any DisplayControl

    init(control: any DisplayControl = SystemDisplayControl()) { self.control = control }

    var needsRestoration: Bool { original.withLock { $0 != nil } }

    func prepare(_ diagnostic: DisplayDiagnostic, level: Double = 1) throws {
        let display = try DimmingEligibility.validate(diagnostic)
        try original.withLock { saved in
            guard saved == nil else { throw DimmingError.restorationRequired }
            let modeID = try control.modeID(for: display)
            let brightness = try control.brightness(display.displayID)
            let automatic = try control.automaticBrightness(display.displayID)
            let table = try control.readTable(display.displayID)
            let requested = try BrightnessCurve.table(from: table, level: level)
            let snapshot = OriginalTransferStore(display: display, modeID: modeID, table: table,
                                                 brightness: brightness.level, automaticBrightness: automatic)
            try validateCurrentDisplay(snapshot)
            saved = snapshot
            // Verify that the saved table can be restored before applying attenuation.
            try write(table, to: snapshot)
            try setAutomaticBrightness(false, on: snapshot)
            // Apply attenuation first to avoid a bright flash when raising the hardware level.
            try write(requested, to: snapshot)
            try setBrightness(1, on: snapshot)
            guard BrightnessCurve.matches(try control.readTable(display.displayID), requested) else {
                throw DimmingError.verificationFailed
            }
        }
    }

    func apply(level: Double) throws {
        try original.withLock { saved in
            guard let saved else { throw DimmingError.inactive }
            guard !saved.tableRestored else { throw DimmingError.restorationRequired }
            try requireMaximumBrightness(saved.display.displayID)
            try write(BrightnessCurve.table(from: saved.table, level: level), to: saved)
        }
    }

    func restore() throws {
        try original.withLock { try restore(&$0) }
    }

    func restoreBeforeReconfiguration(displayID: CGDirectDisplayID) -> Result<Void, Error>? {
        original.withLock { saved in
            guard var snapshot = saved, snapshot.display.displayID == displayID else { return nil }
            return Result {
                if !snapshot.tableRestored {
                    try write(snapshot.table, to: snapshot)
                    snapshot.tableRestored = true
                    saved = snapshot
                }
            }
        }
    }

    @discardableResult
    func checkHardwareBrightness() throws -> HardwareBrightness {
        try original.withLock { saved in
            guard let saved else { throw DimmingError.inactive }
            guard !saved.tableRestored else { throw DimmingError.restorationRequired }
            try validateCurrentDisplay(saved)
            return try requireMaximumBrightness(saved.display.displayID)
        }
    }

    @discardableResult
    private func requireMaximumBrightness(_ displayID: CGDirectDisplayID) throws -> HardwareBrightness {
        let brightness = try control.brightness(displayID)
        guard brightness.level == 1 else {
            throw DimmingError.hardwareNotMaximum
        }
        guard try !control.automaticBrightness(displayID) else { throw HardwareBrightnessError.automaticVerification }
        return brightness
    }

    private func restore(_ saved: inout OriginalTransferStore?) throws {
        guard var snapshot = saved else { return }
        if !snapshot.tableRestored {
            try write(snapshot.table, to: snapshot)
            snapshot.tableRestored = true
            saved = snapshot
        }
        try setBrightness(snapshot.brightness, on: snapshot)
        try setAutomaticBrightness(snapshot.automaticBrightness, on: snapshot)
        saved = nil
    }

    private func validateCurrentDisplay(_ snapshot: OriginalTransferStore) throws {
        guard try control.modeID(for: snapshot.display) == snapshot.modeID else {
            throw DimmingError.displayChanged
        }
    }

    private func setBrightness(_ level: Float, on snapshot: OriginalTransferStore) throws {
        _ = try control.modeID(for: snapshot.display)
        let id = snapshot.display.displayID
        try control.setBrightness(level, on: id)
        let actual = try control.brightness(id).level
        guard level == 1 ? actual == 1 : abs(actual - level) <= 0.001 else {
            throw HardwareBrightnessError.verificationFailed
        }
    }

    private func setAutomaticBrightness(_ enabled: Bool, on snapshot: OriginalTransferStore) throws {
        _ = try control.modeID(for: snapshot.display)
        let id = snapshot.display.displayID
        try control.setAutomaticBrightness(enabled, on: id)
        guard try control.automaticBrightness(id) == enabled else { throw HardwareBrightnessError.automaticVerification }
    }

    private func write(_ table: TransferTable, to snapshot: OriginalTransferStore) throws {
        try validateCurrentDisplay(snapshot)
        let display = snapshot.display
        try control.writeTable(table, to: display.displayID)
        let actual = try control.readTable(display.displayID)
        guard BrightnessCurve.matches(actual, table) else { throw DimmingError.verificationFailed }
    }
}
