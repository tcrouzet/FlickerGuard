import AppKit
import ColorSync
import CoreGraphics
import IOKit
import IOKit.graphics

enum DisplayReadError: LocalizedError {
    case enumeration(Int32)
    case noInternalDisplay
    case ambiguousInternalDisplay
    case unavailableDisplay
    case unavailableTransferTable
    case transferRead(Int32)
    case invalidTransferTable

    var errorDescription: String? {
        switch self {
        case .enumeration(let code):
            tr("error.enumeration", ["code": String(code)])
        case .noInternalDisplay:
            tr("error.noInternalDisplay")
        case .ambiguousInternalDisplay:
            tr("error.ambiguousDisplay")
        case .unavailableDisplay:
            tr("error.unavailableDisplay")
        case .unavailableTransferTable:
            tr("error.unavailableTable")
        case .transferRead(let code):
            tr("error.transferRead", ["code": String(code)])
        case .invalidTransferTable:
            tr("error.invalidTable")
        }
    }
}

@MainActor
enum InternalDisplayDetector {
    static func detect() throws -> DisplayIdentity {
        var count: UInt32 = 0
        var result = CGGetOnlineDisplayList(0, nil, &count)
        guard result == .success else {
            throw DisplayReadError.enumeration(result.rawValue)
        }
        guard count > 0 else { throw DisplayReadError.noInternalDisplay }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        result = CGGetOnlineDisplayList(count, &displays, &count)
        guard result == .success else {
            throw DisplayReadError.enumeration(result.rawValue)
        }
        let internalDisplays = displays.prefix(Int(count)).filter {
            CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0
        }
        guard let displayID = internalDisplays.first else {
            throw DisplayReadError.noInternalDisplay
        }
        guard internalDisplays.count == 1 else {
            throw DisplayReadError.ambiguousInternalDisplay
        }

        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        let info = registryInfo(vendorID: vendorID, productID: productID)
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        let names = info?[kDisplayProductName] as? [String: String]
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        return DisplayIdentity(
            displayID: displayID,
            isBuiltin: true,
            macModel: macModel(),
            manufacturer: manufacturerCode(vendorID),
            modelName: screen?.localizedName ?? names?.values.sorted().first,
            vendorID: vendorID,
            productID: productID,
            hardwareID: uuid.map { CFUUIDCreateString(nil, $0) as String },
            edid: (info?[kIODisplayEDIDKey] as? Data).map { Array($0) }
        )
    }

    private static func registryInfo(vendorID: UInt32, productID: UInt32) -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var matches: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?
                .takeRetainedValue() as? [String: Any],
                (info[kDisplayVendorID] as? NSNumber)?.uint32Value == vendorID,
                (info[kDisplayProductID] as? NSNumber)?.uint32Value == productID else { continue }
            matches.append(info)
        }
        // Duplicate identifiers cannot establish which physical panel supplied the EDID.
        return matches.count == 1 ? matches[0] : nil
    }

    static func macModel() -> String? {
        let platform = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/")
        guard platform != 0 else { return nil }
        defer { IOObjectRelease(platform) }
        guard let data = IORegistryEntryCreateCFProperty(platform, "model" as CFString, nil, 0)?
            .takeRetainedValue() as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
    }

    static func manufacturerCode(_ vendorID: UInt32) -> String? {
        guard vendorID > 0, vendorID <= 0x7FFF else { return nil }
        let letters = [10, 5, 0].map { (vendorID >> $0) & 0x1F }
        guard letters.allSatisfy({ (1...26).contains($0) }) else { return nil }
        return String(letters.map { Character(UnicodeScalar($0 + 64)!) })
    }
}
