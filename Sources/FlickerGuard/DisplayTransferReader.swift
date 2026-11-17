import CoreGraphics

struct TransferTable: Equatable, Sendable {
    let red: [CGGammaValue]
    let green: [CGGammaValue]
    let blue: [CGGammaValue]

    init(red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) throws {
        guard !red.isEmpty, red.count == green.count, red.count == blue.count,
              [red, green, blue].allSatisfy({ channel in
                  channel.allSatisfy { $0.isFinite && (0...1).contains($0) }
              }) else { throw DisplayReadError.invalidTransferTable }
        self.red = red
        self.green = green
        self.blue = blue
    }
}

enum DisplayTransferReader {
    static func read(displayID: CGDirectDisplayID) throws -> TransferTable {
        guard displayID != kCGNullDirectDisplay,
              CGDisplayIsBuiltin(displayID) != 0, CGDisplayIsActive(displayID) != 0 else {
            throw DisplayReadError.unavailableDisplay
        }
        let capacity = CGDisplayGammaTableCapacity(displayID)
        guard capacity > 0, capacity <= 65_536 else {
            throw DisplayReadError.unavailableTransferTable
        }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &sampleCount)
        guard result == .success else { throw DisplayReadError.transferRead(result.rawValue) }
        guard sampleCount > 0, sampleCount <= capacity else {
            throw DisplayReadError.invalidTransferTable
        }
        return try TransferTable(
            red: Array(red.prefix(Int(sampleCount))),
            green: Array(green.prefix(Int(sampleCount))),
            blue: Array(blue.prefix(Int(sampleCount)))
        )
    }
}
