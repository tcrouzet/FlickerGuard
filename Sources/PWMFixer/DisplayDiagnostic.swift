import Foundation

struct DisplayDiagnostic {
    let display: DisplayIdentity?
    let isRecognizedOLED: Bool
    let transferTable: TransferTable?
    var hardwareBrightness: Result<HardwareBrightness, Error>?
    let errorMessage: String?

    var status: String {
        guard display != nil else {
            return tr("diag.noDisplay")
        }
        return isRecognizedOLED
            ? tr("diag.oledRecognized")
            : tr("diag.oledUnverified")
    }

    @MainActor
    static func capture() -> DisplayDiagnostic {
        let display: DisplayIdentity
        do {
            display = try InternalDisplayDetector.detect()
        } catch {
            return DisplayDiagnostic(
                display: nil, isRecognizedOLED: false, transferTable: nil, hardwareBrightness: nil,
                errorMessage: error.localizedDescription
            )
        }
        let recognized = OLEDSignatureDatabase.recognizes(display)
        let brightness = Result { try HardwareBrightnessReader.read(displayID: display.displayID) }
        do {
            let table = try DisplayTransferReader.read(displayID: display.displayID)
            return DisplayDiagnostic(
                display: display, isRecognizedOLED: recognized, transferTable: table,
                hardwareBrightness: brightness, errorMessage: nil
            )
        } catch {
            return DisplayDiagnostic(
                display: display, isRecognizedOLED: recognized, transferTable: nil,
                hardwareBrightness: brightness,
                errorMessage: error.localizedDescription
            )
        }
    }

    var report: String {
        var lines = [tr("diag.title"), status]
        if OLEDSignatureDatabase.signatures.isEmpty {
            lines.append(tr("diag.emptyDatabase"))
        }
        if let display {
            lines += [
                tr("diag.macModel", ["value": display.macModel ?? tr("common.unavailable")]),
                tr("diag.manufacturer", ["value": display.manufacturer ?? tr("common.unavailable")]),
                tr("diag.model", ["value": display.modelName ?? tr("common.unavailable")]),
                tr("diag.displayID", ["value": String(display.displayID)]),
                tr("diag.vendorID", ["value": String(format: "0x%04X", display.vendorID)]),
                tr("diag.productID", ["value": String(format: "0x%04X", display.productID)]),
                tr("diag.uuid", ["value": display.hardwareID ?? tr("common.unavailable")]),
                tr("diag.signature", ["value": isRecognizedOLED ? tr("diag.recognized") : tr("diag.unverified")])
            ]
            if let edid = display.edid, !edid.isEmpty {
                lines.append(tr("diag.edid", ["count": edid.count.formatted()]))
                lines.append(edid.map { String(format: "%02X", $0) }.joined(separator: " "))
            } else {
                lines.append(tr("diag.edidUnavailable"))
            }
        }
        switch hardwareBrightness {
        case .success(let brightness):
            lines.append(tr("diag.hardware", ["level": brightness.level.formatted(.percent.precision(.fractionLength(0)))]))
        case .failure(let error):
            lines.append(tr("diag.hardwareError", ["error": error.localizedDescription]))
        case nil:
            lines.append(tr("diag.hardwareNotRead"))
        }
        if let table = transferTable {
            lines.append(tr("diag.table", ["count": table.red.count.formatted()]))
        } else {
            lines.append(tr("diag.tableUnavailable"))
        }
        if let errorMessage { lines.append(tr("diag.error", ["error": errorMessage])) }
        return lines.joined(separator: "\n")
    }
}
