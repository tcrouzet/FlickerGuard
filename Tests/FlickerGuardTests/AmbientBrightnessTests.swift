import Foundation
import Testing
@testable import FlickerGuard

@Test func automaticIndoorTargetsUseStrongerSoftwareAttenuation() throws {
    let curve = AmbientBrightness()
    #expect(try curve.requestedLevel(for: 50) < 0.2)
    #expect(try curve.requestedLevel(for: 55) < 0.2)
    #expect(try curve.requestedLevel(for: 100) <= 0.3)
    #expect(try curve.requestedLevel(for: 200) < 0.4)
    #expect(try curve.requestedLevel(for: 1000) < 0.6)
}

@Test func ambientDiagnosticExposesOnlyTheLastValidLuxReading() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var diagnostic = AmbientBrightnessDiagnostic()
    #expect(diagnostic.measuredLux == nil)
    _ = try diagnostic.observe(lux: 54.5, curve: AmbientBrightness(), current: 0.2, at: start)
    #expect(diagnostic.measuredLux == 54.5)
    for invalid: Double in [.nan, .infinity, -1] {
        #expect(throws: AmbientLightError.self) { try diagnostic.observe(lux: invalid, curve: AmbientBrightness(), current: 0.2, at: start) }
        #expect(diagnostic.measuredLux == 54.5)
    }
    _ = try diagnostic.observe(lux: 0, curve: AmbientBrightness(), current: 0.2, at: start)
    #expect(diagnostic.measuredLux == 0)
}

@Test func darknessAndManualSelectionCanReachOnePercent() throws {
    #expect(try AmbientBrightness().requestedLevel(for: 0) == 0.01)
    var settings = SoftwareBrightnessSettings()
    try settings.selectManual(0.01)
    #expect(!settings.automatic)
    #expect(try settings.activationLevel(hardware: HardwareBrightness(level: 1), ambientLux: nil) == 0.01)
    let table = try TransferTable(red: [0, 1], green: [0, 0.8], blue: [0, 0.6])
    #expect(try BrightnessCurve.table(from: table, level: 0.01).red == [0, 0.01])
}

@Test func ambientAdjustmentTracksLightWithoutJumpingOrReactingToSmallNoise() throws {
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    #expect(try curve.level(for: 100, from: 0.5) == 0.5)
    #expect(try curve.level(for: 101, from: 0.5) == 0.5)
    #expect(try curve.level(for: 1000, from: 0.5) == 0.52)
    #expect(try curve.level(for: 0, from: 0.5) == 0.48)
    var level = 0.5
    for _ in 0..<100 { level = try curve.level(for: 201, from: level) }
    #expect(abs(level - 0.6) < 0.01)
    let brighterPreference = try AmbientBrightness(lux: 100, level: 0.7)
    #expect(try brighterPreference.level(for: 100, from: 0.7) == 0.7)
}

@Test func ambientAdjustmentReachesBothLimitsIncludingNoAttenuationAtMaximum() throws {
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    var bright = 0.5
    var dark = 0.5
    for _ in 0..<100 {
        bright = try curve.level(for: 1_000_000, from: bright)
        dark = try curve.level(for: 0, from: dark)
    }
    #expect(bright == 1)
    #expect(dark == 0.01)
    #expect(try curve.level(for: .greatestFiniteMagnitude, from: 0.5).isFinite)
}

@Test func ambientAdjustmentRefusesInvalidSensorAndSoftwareValues() throws {
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    for lux: Double in [-1, .nan, .infinity, -.infinity] {
        #expect(throws: AmbientLightError.self) { try AmbientBrightness(lux: lux, level: 0.5) }
        #expect(throws: AmbientLightError.self) { try curve.level(for: lux, from: 0.5) }
    }
    for level: Double in [0, 0.009, 1.001, .nan, .infinity, -.infinity] {
        #expect(throws: DimmingError.self) { try AmbientBrightness(lux: 100, level: level) }
        #expect(throws: DimmingError.self) { try curve.level(for: 100, from: level) }
    }
    #expect(try AmbientBrightness(lux: 0, level: 0.1).level(for: 0, from: 0.1) == 0.1)
}

@Test func softwarePreferencesRememberLevelAndModeAcrossActivation() throws {
    var settings = SoftwareBrightnessSettings()
    settings.automatic = false
    let original = try HardwareBrightness(level: 0.4)
    #expect(abs(try settings.activationLevel(hardware: original, ambientLux: nil) - 0.4) < 0.00001)
    #expect(try settings.activationLevel(hardware: HardwareBrightness(level: 0), ambientLux: nil) == 0.01)
    try settings.remember(0.63)
    #expect(try settings.activationLevel(hardware: HardwareBrightness(level: 1), ambientLux: nil) == 0.63)
    #expect(try settings.activationLevel(hardware: original, ambientLux: nil) == 0.63)
    #expect(!settings.automatic)
    settings.automatic = true
    #expect(settings.level == 0.63)
    for value: Double in [.nan, .infinity, 0, 1.01] {
        #expect(throws: DimmingError.self) { try settings.remember(value) }
        #expect(settings.level == 0.63)
    }
}

@Test func automaticStartupAt35LuxDoesNotAnchorToHardwareMaximum() throws {
    let settings = SoftwareBrightnessSettings()
    let maximum = try HardwareBrightness(level: 1)
    let level = try settings.activationLevel(hardware: maximum, ambientLux: 35)
    #expect(abs(level - 0.10117135186905174) < 0.000000000001)
    #expect(level < 1)
    let start = Date(timeIntervalSince1970: 1_000)
    var diagnostic = AmbientBrightnessDiagnostic()
    _ = try diagnostic.observe(lux: 35, curve: AmbientBrightness(), current: level, at: start)
    let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(2))
    #expect(diagnostic.report(at: start).contains(tr("report.ambientTarget", ["level": level.formatted(percent)])))
    let lowHardware = try HardwareBrightness(level: 0.2)
    #expect(try settings.activationLevel(hardware: lowHardware, ambientLux: 35) == level)
    #expect(try settings.activationLevel(hardware: maximum, ambientLux: 100) == 0.25)
    #expect(abs(try settings.activationLevel(hardware: maximum, ambientLux: 200) - 0.34928402084271337) < 0.000000000001)
}

@Test func manualChoiceDisablesAutomaticAndSurvivesReactivationAndAmbientMovement() throws {
    var settings = SoftwareBrightnessSettings()
    let hardware = try HardwareBrightness(level: 1)
    try settings.selectManual(0.21)
    #expect(!settings.automatic)
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: nil) == 0.21)
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: 35) == 0.21)
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: 71) == 0.21)
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: .nan) == 0.21)
    settings.automatic = true
    #expect(abs(try settings.activationLevel(hardware: hardware, ambientLux: 35) - 0.10117135186905174) < 0.000000000001)
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: 100) == 0.25)
    try settings.selectManual(0.81)
    #expect(!settings.automatic)
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: 35) == 0.81)
}

@Test func automaticAndManualModesValidateInputsBeforeChangingTheSelection() throws {
    var settings = SoftwareBrightnessSettings()
    let hardware = try HardwareBrightness(level: 1)
    #expect(throws: AmbientLightError.self) { try settings.activationLevel(hardware: hardware, ambientLux: nil) }
    for lux: Double in [-1, .nan, .infinity] {
        #expect(throws: AmbientLightError.self) { try settings.activationLevel(hardware: hardware, ambientLux: lux) }
    }
    for level: Double in [0, .nan, .infinity, 1.01] {
        #expect(throws: DimmingError.self) { try settings.selectManual(level) }
        #expect(settings.automatic)
        #expect(settings.level == 1)
    }
    try settings.selectManual(0.21)
    for level: Double in [0, .nan, .infinity, 1.01] {
        #expect(throws: DimmingError.self) { try settings.selectManual(level) }
        #expect(!settings.automatic)
        #expect(settings.level == 0.21)
    }
    #expect(try settings.activationLevel(hardware: hardware, ambientLux: nil) == 0.21)
}

@Test func manualSelectionAtTheCurrentLevelStillDisablesAutomaticAdjustment() throws {
    var settings = SoftwareBrightnessSettings()
    try settings.remember(0.63)
    #expect(settings.automatic)
    try settings.selectManual(0.63)
    #expect(!settings.automatic)
    #expect(settings.level == 0.63)
}

@Test @MainActor func automaticToggleDoesNotActivateDimmingOrResetPreferences() {
    let state = AppState()
    #expect(state.automaticAdjustment)
    #expect(state.ambientLightText == tr("ui.ambientInactive"))
    #expect(state.report.contains(tr("report.ambientInactive")))
    #expect(state.report.contains(tr("report.softwareApplied", ["level": tr("common.unavailable")])))
    state.setAutomaticAdjustment(false)
    #expect(state.ambientLightText == tr("ui.ambientInactive"))
    #expect(!state.automaticAdjustment)
    #expect(!state.report.contains(tr("report.ambientInactive")))
    #expect(state.restoreOriginal())
    #expect(!state.automaticAdjustment)
    state.setAutomaticAdjustment(true)
    #expect(state.automaticAdjustment)
    #expect(!state.isActive)
    #expect(state.softwareLevel == 1)
    #expect(!state.needsRestoration)
}

@Test func ambientTargetsUseTenPointsPerDoublingBeforeTransition() throws {
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    #expect(try curve.requestedLevel(for: 100) == 0.5)
    #expect(abs(try curve.requestedLevel(for: 201) - 0.6) < 0.000000000001)
    #expect(abs(try curve.requestedLevel(for: 49.5) - 0.4) < 0.000000000001)
    #expect(try curve.requestedLevel(for: 1000) < 1)
    #expect(try curve.requestedLevel(for: 1_000_000) == 1)
    #expect(try curve.requestedLevel(for: 0) == 0.01)
    #expect(try curve.level(for: 130, from: 0.5) == 0.52)
    #expect(try curve.level(for: 201, from: 0.5) == 0.52)
}

@Test func ambientDiagnosticSeparatesRequestedLevelFromTheNextStepAndTracksActivity() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    var diagnostic = AmbientBrightnessDiagnostic()
    #expect(diagnostic.report(at: start) == [tr("report.ambientWaiting")])
    #expect(try diagnostic.observe(lux: 201, curve: curve, current: 0.5, at: start) == 0.52)
    let report = diagnostic.report(at: start.addingTimeInterval(2))
    let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(2))
    let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
    #expect(report.contains(tr("report.ambientLux", ["value": 201.0.formatted(number)])))
    #expect(report.contains(tr("report.ambientTarget", ["level": 0.6.formatted(percent)])))
    #expect(report.contains(tr("report.ambientNext", ["level": 0.52.formatted(percent)])))
    #expect(report.contains(tr("report.ambientReference", ["lux": 100.0.formatted(number), "level": 0.5.formatted(percent)])))
    #expect(report.contains(tr("report.ambientGain", ["value": 10.formatted()])))
    #expect(report.contains(tr("report.ambientReads", ["count": 1.formatted(), "seconds": 2.0.formatted(number)])))
    #expect(report.contains(tr("report.ambientReason", ["value": tr("report.ambientRamping")])))
    #expect(report.contains(tr("report.ambientNeverAdjusted")))
    _ = try diagnostic.observe(lux: 201, curve: curve, current: 0.52, at: start.addingTimeInterval(1))
    diagnostic.didAdjust(at: start.addingTimeInterval(1))
    let later = diagnostic.report(at: start.addingTimeInterval(3))
    #expect(later.contains(tr("report.ambientReads", ["count": 2.formatted(), "seconds": 2.0.formatted(number)])))
    #expect(later.contains(tr("report.ambientAdjusted", ["seconds": 2.0.formatted(number)])))
    #expect(!later.contains(tr("report.ambientNeverAdjusted")))
}

@Test func ambientDiagnosticExplainsUnchangedTargetsAndRejectsInvalidObservations() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    var diagnostic = AmbientBrightnessDiagnostic()
    _ = try diagnostic.observe(lux: 100, curve: curve, current: 0.5, at: start)
    #expect(diagnostic.report(at: start).contains(tr("report.ambientReason", ["value": tr("report.ambientReached")])))
    _ = try diagnostic.observe(lux: 101, curve: curve, current: 0.5, at: start)
    #expect(diagnostic.report(at: start).contains(tr("report.ambientReason", ["value": tr("report.ambientThreshold")])))
    let validReport = diagnostic.report(at: start)
    for lux: Double in [.nan, .infinity, -1] {
        #expect(throws: AmbientLightError.self) { try diagnostic.observe(lux: lux, curve: curve, current: 0.5, at: start) }
        #expect(diagnostic.report(at: start) == validReport)
    }
    #expect(throws: DimmingError.self) { try diagnostic.observe(lux: 101, curve: curve, current: .nan, at: start) }
    #expect(diagnostic.report(at: start) == validReport)
}

@Test func recordedSmallAmbientFluctuationsCauseNoSoftwareAdjustment() throws {
    let samples: [Double] = [40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 36, 39, 44, 47, 45, 46, 46, 46, 46, 47, 48, 48, 48, 48, 48, 48]
    #expect(!samples.isEmpty)
    let firstLux = try #require(samples.first)
    let curve = AmbientBrightness()
    let initial = try curve.requestedLevel(for: firstLux)
    var diagnostic = AmbientBrightnessDiagnostic()
    let start = Date(timeIntervalSince1970: 1_000)
    for (index, lux) in samples.enumerated() {
        let next = try diagnostic.observe(lux: lux, curve: curve, current: initial, at: start.addingTimeInterval(Double(index)))
        #expect(next == initial)
    }
    let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(2))
    #expect(diagnostic.report(at: start).contains(tr("report.ambientAccepted", ["level": initial.formatted(percent)])))
}

@Test func significantAmbientChangeRequiresConfirmationAndCompletesExactlyOnce() throws {
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    let start = Date(timeIntervalSince1970: 1_000)
    var diagnostic = AmbientBrightnessDiagnostic()
    #expect(try diagnostic.observe(lux: 100, curve: curve, current: 0.5, at: start) == 0.5)
    #expect(try diagnostic.observe(lux: 201, curve: curve, current: 0.5, at: start.addingTimeInterval(0.25)) == 0.5)
    #expect(diagnostic.report(at: start).contains(tr("report.ambientReason", ["value": tr("report.ambientStabilizing")])))
    #expect(try diagnostic.observe(lux: 201, curve: curve, current: 0.5, at: start.addingTimeInterval(2)) == 0.5)
    var level = try diagnostic.observe(lux: 201, curve: curve, current: 0.5, at: start.addingTimeInterval(2.25))
    #expect(level == 0.52)
    for step in 1...20 {
        let previous = level
        level = try diagnostic.observe(lux: 201, curve: curve, current: level, at: start.addingTimeInterval(2.25 + Double(step) * 0.25))
        #expect(level >= previous)
        #expect(level - previous <= 0.020000000001)
    }
    #expect(level == 0.6)
    for step in 1...20 {
        #expect(try diagnostic.observe(lux: 201, curve: curve, current: level, at: start.addingTimeInterval(10 + Double(step))) == level)
    }
    for (initial, limit) in [(0.95, 1.0), (0.05, 0.01)] {
        var stabilizer = AmbientBrightnessStabilizer()
        #expect(try stabilizer.target(for: initial, at: start) == initial)
        #expect(try stabilizer.target(for: limit, at: start.addingTimeInterval(0.25)) == initial)
        #expect(try stabilizer.target(for: limit, at: start.addingTimeInterval(2.25)) == limit)
        #expect(try stabilizer.target(for: limit, at: start.addingTimeInterval(3)) == limit)
        #expect(!stabilizer.isWaiting)
    }
}

@Test func transientAndReversingAmbientChangesRestartConfirmation() throws {
    let curve = try AmbientBrightness(lux: 100, level: 0.5)
    let start = Date(timeIntervalSince1970: 1_000)
    var transient = AmbientBrightnessDiagnostic()
    for (seconds, lux) in [(0.0, 100.0), (0.25, 201), (1, 100), (2.25, 201)] {
        #expect(try transient.observe(lux: lux, curve: curve, current: 0.5, at: start.addingTimeInterval(seconds)) == 0.5)
    }
    #expect(try transient.observe(lux: 201, curve: curve, current: 0.5, at: start.addingTimeInterval(4.25)) == 0.52)
    var diagnostic = AmbientBrightnessDiagnostic()
    for (seconds, lux) in [(0.0, 100.0), (0.25, 201), (1, 100), (1.25, 201), (2, 0), (2.25, 201), (4, 201)] {
        #expect(try diagnostic.observe(lux: lux, curve: curve, current: 0.5, at: start.addingTimeInterval(seconds)) == 0.5)
    }
    #expect(try diagnostic.observe(lux: 201, curve: curve, current: 0.5, at: start.addingTimeInterval(4.25)) == 0.52)
}

@Test func gradualAmbientDriftIsComparedWithTheRetainedTarget() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var stabilizer = AmbientBrightnessStabilizer()
    #expect(try stabilizer.target(for: 0.5, at: start) == 0.5)
    for step in 1...7 {
        #expect(try stabilizer.target(for: 0.5 + Double(step) / 100, at: start.addingTimeInterval(Double(step))) == 0.5)
    }
    #expect(try stabilizer.target(for: 0.59, at: start.addingTimeInterval(8)) == 0.5)
    #expect(try stabilizer.target(for: 0.60, at: start.addingTimeInterval(9)) == 0.5)
    #expect(try stabilizer.target(for: 0.61, at: start.addingTimeInterval(10)) == 0.61)
    for invalid: Double in [.nan, .infinity, 0, 1.1] {
        #expect(throws: DimmingError.self) { try stabilizer.target(for: invalid, at: start.addingTimeInterval(11)) }
    }
    #expect(try stabilizer.target(for: 0.61, at: start.addingTimeInterval(12)) == 0.61)
}

@Test func manualChoiceImmediatelyTakesOverAPendingAutomaticChange() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let original = try AmbientBrightness(lux: 100, level: 0.5)
    var diagnostic = AmbientBrightnessDiagnostic()
    _ = try diagnostic.observe(lux: 100, curve: original, current: 0.5, at: start)
    _ = try diagnostic.observe(lux: 201, curve: original, current: 0.5, at: start.addingTimeInterval(0.25))
    #expect(diagnostic.report(at: start).contains(tr("report.ambientReason", ["value": tr("report.ambientStabilizing")])))
    var settings = SoftwareBrightnessSettings()
    try settings.selectManual(0.21)
    #expect(!settings.automatic)
    #expect(settings.level == 0.21)
    #expect(try settings.activationLevel(hardware: HardwareBrightness(level: 1), ambientLux: 201) == 0.21)
}
