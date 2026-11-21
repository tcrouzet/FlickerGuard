import CoreGraphics
import Foundation
import Testing
@testable import PWMFixer

@Test func applicationExclusionsAreOptInAndMatchExactIdentifiers() {
    var settings = ApplicationExclusions()
    #expect(settings.shouldPause(bundleIdentifier: "editor", browserIsFullscreen: true) == false)
    settings.applications["editor"] = "Photo editor"
    #expect(settings.shouldPause(bundleIdentifier: "editor", browserIsFullscreen: false) == true)
    #expect(settings.shouldPause(bundleIdentifier: "editor.helper", browserIsFullscreen: false) == false)
    #expect(settings.shouldPause(bundleIdentifier: nil, browserIsFullscreen: true) == false)
    settings.applications.removeValue(forKey: "editor")
    #expect(settings.shouldPause(bundleIdentifier: "editor", browserIsFullscreen: false) == false)
}

@Test func fullscreenBrowserPausingIsSeparateAndPreservesUnknownReadings() {
    var settings = ApplicationExclusions(browserFullscreen: true)
    #expect(settings.shouldPause(bundleIdentifier: "browser", browserIsFullscreen: true) == true)
    #expect(settings.shouldPause(bundleIdentifier: "browser", browserIsFullscreen: false) == false)
    #expect(settings.shouldPause(bundleIdentifier: "browser", browserIsFullscreen: nil) == nil)
    settings.applications["browser"] = "Browser"
    #expect(settings.shouldPause(bundleIdentifier: "browser", browserIsFullscreen: nil) == true)
}

@Test func applicationPausesRetainIntentThroughSleepAndRequireLeavingTheApp() {
    var recovery = DisplayResumeState()
    recovery.setApplicationBlocked(true)
    recovery.interrupt(wasActive: true, sleeping: false)
    #expect(recovery.pending)
    #expect(!recovery.shouldResume)
    #expect(!recovery.canReadAmbient())
    recovery.interrupt(wasActive: false, sleeping: true)
    recovery.setApplicationBlocked(false)
    #expect(!recovery.shouldResume)
    recovery.wake()
    #expect(recovery.shouldResume)
    recovery.setApplicationBlocked(true)
    #expect(!recovery.shouldResume)
    recovery.setApplicationBlocked(false)
    #expect(recovery.shouldResume)
}

@Test func manuallyDisabledAppsNeverEnableThemselvesAfterAnException() {
    var recovery = DisplayResumeState()
    recovery.setApplicationBlocked(true)
    recovery.interrupt(wasActive: true, sleeping: false)
    recovery.cancel()
    recovery.setApplicationBlocked(false)
    #expect(!recovery.pending)
    #expect(!recovery.shouldResume)
    recovery.setApplicationBlocked(true)
    recovery.interrupt(wasActive: false, sleeping: true)
    recovery.wake()
    recovery.setApplicationBlocked(false)
    #expect(!recovery.shouldResume)
}

@Test func fullscreenDetectionTargetsOnlyTheBuiltInDisplay() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    #expect(BrowserFullscreenReader.matchesDisplay(window: screen, display: screen, nativeFullscreen: false, browserControlsVisible: false) == false)
    #expect(BrowserFullscreenReader.matchesDisplay(window: CGRect(x: 0, y: 38, width: 1512, height: 944), display: screen, nativeFullscreen: true, browserControlsVisible: false) == true)
    #expect(BrowserFullscreenReader.matchesDisplay(window: CGRect(x: 0, y: 38, width: 1512, height: 944), display: screen, nativeFullscreen: false, browserControlsVisible: false) == false)
    #expect(BrowserFullscreenReader.matchesDisplay(window: CGRect(x: 1512, y: 0, width: 1920, height: 1080), display: screen, nativeFullscreen: true, browserControlsVisible: false) == false)
    #expect(BrowserFullscreenReader.matchesDisplay(window: .zero, display: screen, nativeFullscreen: true, browserControlsVisible: false) == false)
    #expect(BrowserFullscreenReader.matchesDisplay(window: screen, display: screen, nativeFullscreen: true, browserControlsVisible: true) == false)
    #expect(BrowserFullscreenReader.matchesDisplay(window: screen, display: screen, nativeFullscreen: true, browserControlsVisible: nil) == nil)
}

@Test func unstableBrowserReadingsCannotAlternatePauseAndResume() {
    let start = Date(timeIntervalSince1970: 1000)
    var state = BrowserPauseState()
    #expect(state.observe(application: "browser", fullscreen: true, at: start) == false)
    #expect(state.observe(application: "browser", fullscreen: true, at: start.addingTimeInterval(1)) == false)
    #expect(state.observe(application: "browser", fullscreen: true, at: start.addingTimeInterval(2)) == true)
    for second in 3...20 {
        #expect(state.observe(application: "browser", fullscreen: second.isMultiple(of: 2), at: start.addingTimeInterval(Double(second))) == true)
    }
    #expect(state.observe(application: "browser", fullscreen: nil, at: start.addingTimeInterval(21)) == true)
    #expect(state.observe(application: "browser", fullscreen: false, at: start.addingTimeInterval(22)) == true)
    #expect(state.observe(application: "browser", fullscreen: false, at: start.addingTimeInterval(23)) == true)
    #expect(state.observe(application: "browser", fullscreen: false, at: start.addingTimeInterval(24)) == false)
}

@Test func unknownAndChangedBrowserContextsRequireFreshConfirmation() {
    let start = Date(timeIntervalSince1970: 1000)
    var state = BrowserPauseState()
    #expect(state.observe(application: "browser", fullscreen: true, at: start) == false)
    #expect(state.observe(application: "browser", fullscreen: nil, at: start.addingTimeInterval(1)) == false)
    #expect(state.observe(application: "browser", fullscreen: true, at: start.addingTimeInterval(2)) == false)
    #expect(state.observe(application: "browser", fullscreen: true, at: start.addingTimeInterval(3)) == false)
    #expect(state.observe(application: "browser", fullscreen: true, at: start.addingTimeInterval(4)) == true)
    #expect(!state.isPaused(for: "other browser"))
    #expect(state.observe(application: "other browser", fullscreen: true, at: start.addingTimeInterval(5)) == false)
    state.reset()
    #expect(!state.isPaused(for: "other browser"))
}
