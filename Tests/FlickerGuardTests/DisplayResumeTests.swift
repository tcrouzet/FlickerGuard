import Foundation
import Testing
@testable import FlickerGuard

@Test func closedLidAndWakeWarmupDoNotChangeTheRetainedAutomaticLevel() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var recovery = DisplayResumeState()
    var settings = SoftwareBrightnessSettings()
    try settings.remember(0.16)
    recovery.interrupt(wasActive: true, sleeping: true)
    #expect(!recovery.canReadAmbient(at: start))
    recovery.wake()
    let restored = try settings.activationLevel(hardware: HardwareBrightness(level: 0.5), ambientLux: 0, resuming: true)
    #expect(restored == 0.16)
    #expect(try settings.activationLevel(hardware: HardwareBrightness(level: 1), ambientLux: nil, resuming: true) == 0.16)
    recovery.didResume(at: start)
    #expect(!recovery.canReadAmbient(at: start.addingTimeInterval(2.99)))
    #expect(recovery.canReadAmbient(at: start.addingTimeInterval(3)))

    var readings = AmbientBrightnessDiagnostic()
    try readings.retainLevel(restored)
    #expect(readings.measuredLux == nil)
    let curve = AmbientBrightness()
    #expect(try readings.observe(lux: 0, curve: curve, current: restored, at: start.addingTimeInterval(3)) == restored)
    #expect(try readings.observe(lux: 55, curve: curve, current: restored, at: start.addingTimeInterval(3.5)) == restored)
    #expect(try readings.observe(lux: 1000, curve: curve, current: restored, at: start.addingTimeInterval(4)) == restored)
    #expect(try readings.observe(lux: 1000, curve: curve, current: restored, at: start.addingTimeInterval(6)) == 0.18)
}

@Test func repeatedSleepEventsPreserveTheRequestUntilWake() {
    var state = DisplayResumeState()
    state.interrupt(wasActive: true, sleeping: true)
    state.interrupt(wasActive: false, sleeping: true)
    state.interrupt(wasActive: false, sleeping: false)
    #expect(state.pending)
    #expect(!state.shouldResume)
    state.wake()
    #expect(state.shouldResume)
    state.wake()
    #expect(state.shouldResume)
}

@Test func manualDisableDuringSleepCancelsAutomaticResume() {
    var state = DisplayResumeState()
    state.interrupt(wasActive: true, sleeping: true)
    state.cancel()
    state.interrupt(wasActive: false, sleeping: false)
    state.wake()
    #expect(!state.pending)
    #expect(!state.shouldResume)
}

@Test func inactiveDisplayDoesNotEnableItselfAfterSleepOrConfigurationChanges() {
    var state = DisplayResumeState()
    state.interrupt(wasActive: false, sleeping: true)
    state.wake()
    state.interrupt(wasActive: false, sleeping: false)
    #expect(!state.shouldResume)
    state.interrupt(wasActive: true, sleeping: false)
    #expect(state.shouldResume)
    state.cancel()
    #expect(!state.shouldResume)
}
