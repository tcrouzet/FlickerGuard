import CoreGraphics
import Testing
@testable import FlickerGuard

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
    #expect(BrowserFullscreenReader.matchesDisplay(window: screen, display: screen, nativeFullscreen: false))
    #expect(BrowserFullscreenReader.matchesDisplay(window: CGRect(x: 0, y: 38, width: 1512, height: 944), display: screen, nativeFullscreen: true))
    #expect(!BrowserFullscreenReader.matchesDisplay(window: CGRect(x: 0, y: 38, width: 1512, height: 944), display: screen, nativeFullscreen: false))
    #expect(!BrowserFullscreenReader.matchesDisplay(window: CGRect(x: 1512, y: 0, width: 1920, height: 1080), display: screen, nativeFullscreen: true))
    #expect(!BrowserFullscreenReader.matchesDisplay(window: .zero, display: screen, nativeFullscreen: true))
}
