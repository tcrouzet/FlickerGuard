struct DisplayIdentity: Equatable, Sendable {
    let displayID: UInt32
    let isBuiltin: Bool
    let macModel: String?
    let manufacturer: String?
    let modelName: String?
    let vendorID: UInt32
    let productID: UInt32
    let hardwareID: String?
    let edid: [UInt8]?
}

struct OLEDDisplaySignature: Sendable {
    let macModel: String
    let manufacturer: String?
    let modelName: String?
    let vendorID: UInt32
    let productID: UInt32?

    func matches(_ display: DisplayIdentity) -> Bool {
        guard display.isBuiltin, !macModel.isEmpty, display.macModel == macModel,
              vendorID != 0, vendorID != 0x756E6B6E,
              display.productID != 0, display.productID != 0x717,
              display.vendorID == vendorID,
              productID == nil || display.productID == productID else {
            return false
        }
        return (manufacturer == nil || manufacturer == display.manufacturer)
            && (modelName == nil || modelName == display.modelName)
    }
}

enum OLEDSignatureDatabase {
    // PROLED model identifiers: https://github.com/libimobiledevice/libirecovery/blob/master/data/devices.txt
    static let signatures = [
        OLEDDisplaySignature(
            macModel: "Mac17,13", manufacturer: "APP", modelName: nil,
            vendorID: 0x0610, productID: 0xA068
        ),
        // Match the other OLED models by Mac identity; their panel IDs have not been collected.
        OLEDDisplaySignature(
            macModel: "Mac17,11", manufacturer: "APP", modelName: nil,
            vendorID: 0x0610, productID: nil
        ),
        OLEDDisplaySignature(
            macModel: "Mac17,12", manufacturer: "APP", modelName: nil,
            vendorID: 0x0610, productID: nil
        ),
        OLEDDisplaySignature(
            macModel: "Mac17,10", manufacturer: "APP", modelName: nil,
            vendorID: 0x0610, productID: nil
        )
    ]

    static func recognizes(_ display: DisplayIdentity) -> Bool {
        signatures.contains { $0.matches(display) }
    }
}
