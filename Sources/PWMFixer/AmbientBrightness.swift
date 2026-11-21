import Darwin
import Foundation

enum AmbientLightError: LocalizedError {
    case unavailable, invalidReading

    var errorDescription: String? {
        switch self {
        case .unavailable: tr("error.ambientUnavailable")
        case .invalidReading: tr("error.ambientReading")
        }
    }
}

enum AmbientLightReader {
    static func read() throws -> Double {
        guard let bezel = dlopen("/System/Library/PrivateFrameworks/BezelServices.framework/BezelServices", RTLD_LAZY | RTLD_LOCAL) else {
            throw AmbientLightError.unavailable
        }
        defer { dlclose(bezel) }
        guard let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL) else {
            throw AmbientLightError.unavailable
        }
        defer { dlclose(io) }
        guard let serviceSymbol = dlsym(bezel, "ALCALSCopyALSServiceClient"),
              let eventSymbol = dlsym(io, "IOHIDServiceClientCopyEvent"),
              let valueSymbol = dlsym(io, "IOHIDEventGetFloatValue") else { throw AmbientLightError.unavailable }
        typealias CopyService = @convention(c) () -> Unmanaged<CFTypeRef>?
        typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
        typealias GetValue = @convention(c) (CFTypeRef, Int32) -> Double
        let copyService = unsafeBitCast(serviceSymbol, to: CopyService.self)
        let copyEvent = unsafeBitCast(eventSymbol, to: CopyEvent.self)
        let getValue = unsafeBitCast(valueSymbol, to: GetValue.self)
        guard let service = copyService()?.takeRetainedValue(),
              let event = copyEvent(service, 12, 0, 0)?.takeRetainedValue() else { throw AmbientLightError.unavailable }
        return try AmbientBrightness.validateLux(getValue(event, 12 << 16))
    }
}

struct AmbientBrightness {
    static let responsePerDoubling = 0.1
    let referenceLux: Double
    let referenceLevel: Double

    init() {
        referenceLux = 100
        referenceLevel = 0.25
    }

    init(lux: Double, level: Double) throws {
        referenceLux = try Self.validateLux(lux)
        guard level.isFinite, BrightnessCurve.range.contains(level) else { throw DimmingError.invalidLevel }
        referenceLevel = level
    }

    @discardableResult
    static func validateLux(_ lux: Double) throws -> Double {
        guard lux.isFinite, lux >= 0 else { throw AmbientLightError.invalidReading }
        return lux
    }

    func requestedLevel(for lux: Double) throws -> Double {
        try Self.validateLux(lux)
        // shortcut: this software-only curve needs display measurements for physical luminance calibration.
        return min(1, max(BrightnessCurve.minimumLevel, referenceLevel + log2((lux + 1) / (referenceLux + 1)) * Self.responsePerDoubling))
    }

    func level(for lux: Double, from current: Double) throws -> Double {
        let target = try requestedLevel(for: lux)
        guard current.isFinite, BrightnessCurve.range.contains(current) else { throw DimmingError.invalidLevel }
        let difference = target - current
        guard abs(difference) >= 0.01 || target == 1 || target == BrightnessCurve.minimumLevel else { return current }
        return try Self.step(toward: target, from: current)
    }

    static func step(toward target: Double, from current: Double) throws -> Double {
        guard target.isFinite, current.isFinite, BrightnessCurve.range.contains(target), BrightnessCurve.range.contains(current) else {
            throw DimmingError.invalidLevel
        }
        let difference = target - current
        if abs(difference) <= 0.02 { return target }
        return current + (difference > 0 ? 0.02 : -0.02)
    }
}

struct AmbientBrightnessStabilizer {
    static let changeThreshold = 0.08
    static let confirmationSeconds = 2.0

    private var acceptedLevel: Double?
    private var pending: (increasing: Bool, since: Date)?

    var isWaiting: Bool { pending != nil }

    mutating func target(for requested: Double, at date: Date) throws -> Double {
        guard requested.isFinite, BrightnessCurve.range.contains(requested) else { throw DimmingError.invalidLevel }
        guard let acceptedLevel else {
            self.acceptedLevel = requested
            return requested
        }
        let difference = requested - acceptedLevel
        let atLimit = requested == BrightnessCurve.minimumLevel || requested == 1
        guard requested != acceptedLevel, abs(difference) >= Self.changeThreshold || atLimit else {
            pending = nil
            return acceptedLevel
        }
        let increasing = difference > 0
        if pending?.increasing != increasing { pending = (increasing, date) }
        if let pending, date.timeIntervalSince(pending.since) >= Self.confirmationSeconds {
            self.acceptedLevel = requested
            self.pending = nil
            return requested
        }
        return acceptedLevel
    }
}

struct AmbientBrightnessDiagnostic {
    private struct Observation {
        let lux: Double
        let curve: AmbientBrightness
        let current: Double
        let target: Double
        let accepted: Double
        let next: Double
        let waiting: Bool
        let date: Date
    }

    private var observation: Observation?
    private var readCount = 0
    private var lastAdjustment: Date?
    private var stabilizer = AmbientBrightnessStabilizer()

    var measuredLux: Double? { observation?.lux }

    mutating func retainLevel(_ level: Double) throws {
        var retained = AmbientBrightnessDiagnostic()
        _ = try retained.stabilizer.target(for: level, at: .distantPast)
        self = retained
    }

    mutating func observe(lux: Double, curve: AmbientBrightness, current: Double, at date: Date = Date()) throws -> Double {
        let target = try curve.requestedLevel(for: lux)
        guard current.isFinite, BrightnessCurve.range.contains(current) else { throw DimmingError.invalidLevel }
        let accepted = try stabilizer.target(for: target, at: date)
        let next = try AmbientBrightness.step(toward: accepted, from: current)
        observation = Observation(lux: lux, curve: curve, current: current, target: target, accepted: accepted,
                                  next: next, waiting: stabilizer.isWaiting, date: date)
        readCount += 1
        return next
    }

    mutating func didAdjust(at date: Date = Date()) { lastAdjustment = date }

    func report(at date: Date = Date()) -> [String] {
        guard let sample = observation else { return [tr("report.ambientWaiting")] }
        let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(2))
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        let reason = sample.waiting ? tr("report.ambientStabilizing")
            : sample.target != sample.accepted ? tr("report.ambientThreshold")
            : sample.next == sample.current ? tr("report.ambientReached") : tr("report.ambientRamping")
        return [
            tr("report.ambientLux", ["value": sample.lux.formatted(number)]),
            tr("report.ambientTarget", ["level": sample.target.formatted(percent)]),
            tr("report.ambientAccepted", ["level": sample.accepted.formatted(percent)]),
            tr("report.ambientStability", ["points": (AmbientBrightnessStabilizer.changeThreshold * 100).formatted(),
                                           "seconds": AmbientBrightnessStabilizer.confirmationSeconds.formatted()]),
            tr("report.ambientNext", ["level": sample.next.formatted(percent)]),
            tr("report.ambientReference", ["lux": sample.curve.referenceLux.formatted(number), "level": sample.curve.referenceLevel.formatted(percent)]),
            tr("report.ambientGain", ["value": (AmbientBrightness.responsePerDoubling * 100).formatted()]),
            tr("report.ambientReads", ["count": readCount.formatted(), "seconds": max(0, date.timeIntervalSince(sample.date)).formatted(number)]),
            tr("report.ambientReason", ["value": reason]),
            lastAdjustment.map { tr("report.ambientAdjusted", ["seconds": max(0, date.timeIntervalSince($0)).formatted(number)]) }
                ?? tr("report.ambientNeverAdjusted")
        ]
    }
}

struct SoftwareBrightnessSettings {
    private(set) var level = 1.0
    var automatic = true
    private var hasPreviousLevel = false

    func activationLevel(hardware: HardwareBrightness, ambientLux: Double?, resuming: Bool = false) throws -> Double {
        if resuming { return level }
        if automatic {
            guard let ambientLux else { throw AmbientLightError.unavailable }
            return try AmbientBrightness().requestedLevel(for: ambientLux)
        }
        return hasPreviousLevel ? level : max(BrightnessCurve.minimumLevel, Double(hardware.level))
    }

    mutating func selectManual(_ level: Double) throws {
        try remember(level)
        automatic = false
    }

    mutating func remember(_ level: Double) throws {
        guard level.isFinite, BrightnessCurve.range.contains(level) else { throw DimmingError.invalidLevel }
        self.level = level
        hasPreviousLevel = true
    }
}
