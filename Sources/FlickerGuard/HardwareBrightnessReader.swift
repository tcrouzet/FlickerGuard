import CoreGraphics
import Darwin
import Foundation

enum HardwareBrightnessError: LocalizedError {
    case unavailableAPI
    case readFailed(Int32)
    case invalidLevel
    case writeFailed(Int32)
    case verificationFailed
    case automaticRead(Int32)
    case automaticWrite(Int32)
    case automaticVerification

    var errorDescription: String? {
        switch self {
        case .unavailableAPI:
            tr("error.hardwareAPI")
        case .readFailed(let code):
            tr("error.hardwareRead", ["code": String(code)])
        case .invalidLevel:
            tr("error.invalidHardwareLevel")
        case .writeFailed(let code): tr("error.hardwareWrite", ["code": String(code)])
        case .verificationFailed: tr("error.hardwareVerification")
        case .automaticRead(let code): tr("error.automaticRead", ["code": String(code)])
        case .automaticWrite(let code): tr("error.automaticWrite", ["code": String(code)])
        case .automaticVerification: tr("error.automaticVerification")
        }
    }
}

struct HardwareBrightness {
    let level: Float

    init(level: Float) throws {
        guard level.isFinite, (0...1).contains(level) else {
            throw HardwareBrightnessError.invalidLevel
        }
        self.level = level
    }

    var percentage: Int { Int((level * 100).rounded()) }
}

enum HardwareBrightnessReader {
    static func read(displayID: CGDirectDisplayID) throws -> HardwareBrightness {
        try withFramework(displayID: displayID) { framework in
            guard let symbol = dlsym(framework, "DisplayServicesGetBrightness") else {
                throw HardwareBrightnessError.unavailableAPI
            }
            typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
            let getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
            var level = Float.nan
            let result = getBrightness(displayID, &level)
            guard result == 0 else { throw HardwareBrightnessError.readFailed(result) }
            return try HardwareBrightness(level: level)
        }
    }

    static func set(_ level: Float, displayID: CGDirectDisplayID) throws {
        _ = try HardwareBrightness(level: level)
        try withFramework(displayID: displayID) { framework in
            guard let symbol = dlsym(framework, "DisplayServicesSetBrightness") else {
                throw HardwareBrightnessError.unavailableAPI
            }
            typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
            let result = unsafeBitCast(symbol, to: SetBrightness.self)(displayID, level)
            guard result == 0 else { throw HardwareBrightnessError.writeFailed(result) }
        }
    }

    static func automaticBrightness(displayID: CGDirectDisplayID) throws -> Bool {
        try withFramework(displayID: displayID) { framework in
            guard let symbol = dlsym(framework, "DisplayServicesAmbientLightCompensationEnabled") else {
                throw HardwareBrightnessError.unavailableAPI
            }
            typealias ReadAutomatic = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
            var enabled = false
            let result = unsafeBitCast(symbol, to: ReadAutomatic.self)(displayID, &enabled)
            guard result == 0 else { throw HardwareBrightnessError.automaticRead(result) }
            return enabled
        }
    }

    static func setAutomaticBrightness(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        try withFramework(displayID: displayID) { framework in
            guard let symbol = dlsym(framework, "DisplayServicesEnableAmbientLightCompensation") else {
                throw HardwareBrightnessError.unavailableAPI
            }
            typealias SetAutomatic = @convention(c) (CGDirectDisplayID, Bool) -> Int32
            let result = unsafeBitCast(symbol, to: SetAutomatic.self)(displayID, enabled)
            guard result == 0 else { throw HardwareBrightnessError.automaticWrite(result) }
        }
    }

    private static func withFramework<T>(displayID: CGDirectDisplayID, _ body: (UnsafeMutableRawPointer) throws -> T) throws -> T {
        guard displayID != kCGNullDirectDisplay,
              CGDisplayIsBuiltin(displayID) != 0, CGDisplayIsActive(displayID) != 0 else {
            throw DisplayReadError.unavailableDisplay
        }
        guard let framework = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else { throw HardwareBrightnessError.unavailableAPI }
        defer { dlclose(framework) }
        return try body(framework)
    }
}
