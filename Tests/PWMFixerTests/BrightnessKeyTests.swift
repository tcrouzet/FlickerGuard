import IOKit.hidsystem
import Testing
@testable import PWMFixer

@Test func brightnessPressesAndRepeatsAdjustOnlyTheSoftwareLevel() {
    let subtype = Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
    let up = (Int(NX_KEYTYPE_BRIGHTNESS_UP) << 16) | (Int(NX_KEYDOWN) << 8)
    let down = (Int(NX_KEYTYPE_BRIGHTNESS_DOWN) << 16) | (Int(NX_KEYDOWN) << 8)
    #expect(BrightnessKeyAction.decode(subtype: subtype, data1: up) == .increase)
    #expect(BrightnessKeyAction.decode(subtype: subtype, data1: down) == .decrease)
    #expect(BrightnessKeyAction.decode(subtype: subtype, data1: down | 1) == .decrease)
    #expect(BrightnessKeyAction.increase.level(from: 0.5) == 0.5625)
    #expect(BrightnessKeyAction.decrease.level(from: 0.5) == 0.4375)
    #expect(BrightnessKeyAction.increase.level(from: 0.99) == 1)
    #expect(BrightnessKeyAction.decrease.level(from: 0.02) == 0.01)
    #expect(BrightnessKeyAction.decrease.level(from: 0.01) == 0.01)
}

@Test func brightnessReleasesAreConsumedWithoutChangingTheLevel() {
    for key in [NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN] {
        let released = (Int(key) << 16) | (Int(NX_KEYUP) << 8)
        #expect(BrightnessKeyAction.decode(subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), data1: released) == .release)
    }
    #expect(BrightnessKeyAction.release.level(from: 0.5) == nil)
}

@Test func otherMediaKeysAndSubtypesRemainUnclaimed() {
    for key in [NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE, NX_KEYTYPE_PLAY, NX_KEYTYPE_ILLUMINATION_UP, NX_KEYTYPE_ILLUMINATION_DOWN] {
        let data = (Int(key) << 16) | (Int(NX_KEYDOWN) << 8)
        #expect(BrightnessKeyAction.decode(subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), data1: data) == nil)
    }
    #expect(BrightnessKeyAction.decode(subtype: 1, data1: Int(NX_KEYTYPE_BRIGHTNESS_UP) << 16) == nil)
}

@Test func malformedBrightnessStatesRequireStoppingCapture() {
    let malformed = (Int(NX_KEYTYPE_BRIGHTNESS_DOWN) << 16) | (0x7F << 8)
    #expect(BrightnessKeyAction.decode(subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), data1: malformed) == .unsupported)
    #expect(BrightnessKeyAction.unsupported.level(from: 0.5) == nil)
}

@Test @MainActor func keyCaptureStartsStoppedAndCanBeStoppedRepeatedly() {
    let interceptor = NativeBrightnessKeyInterceptor()
    #expect(!interceptor.isRunning)
    interceptor.stop()
    interceptor.stop()
    #expect(!interceptor.isRunning)
    let state = AppState()
    state.setSoftwareLevel(0.5, debounce: false)
    #expect(!state.isActive)
    #expect(state.softwareLevel == 1)
    #expect(!state.needsRestoration)
}
