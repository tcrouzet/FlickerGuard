import AppKit
import ApplicationServices

struct ApplicationExclusions {
    var applications: [String: String] = [:]
    var browserFullscreen = false

    func shouldPause(bundleIdentifier: String?, browserIsFullscreen: Bool?) -> Bool? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        if applications[bundleIdentifier] != nil { return true }
        return browserFullscreen ? browserIsFullscreen : false
    }
}

@MainActor
enum BrowserFullscreenReader {
    private static let browserIdentifiers = Set(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        .compactMap { Bundle(url: $0)?.bundleIdentifier })

    static func isBrowser(_ identifier: String) -> Bool {
        browserIdentifiers.contains(identifier)
    }

    static func isFullscreen(pid: pid_t, displayID: CGDirectDisplayID) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.05)
        let attributes = [kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen" as CFString] as CFArray
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, attributes, [], &result) == .success,
              let values = result as? [AnyObject], values.count == 3,
              CFGetTypeID(values[0]) == AXValueGetTypeID(), CFGetTypeID(values[1]) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(values[0] as! AXValue, .cgPoint, &origin),
              AXValueGetValue(values[1] as! AXValue, .cgSize, &dimensions) else { return nil }
        return matchesDisplay(window: CGRect(origin: origin, size: dimensions), display: CGDisplayBounds(displayID), nativeFullscreen: values[2] as? Bool == true)
    }

    nonisolated static func matchesDisplay(window: CGRect, display: CGRect, nativeFullscreen: Bool) -> Bool {
        guard !window.isEmpty, !display.isEmpty,
              window.origin.x.isFinite, window.origin.y.isFinite,
              window.width.isFinite, window.height.isFinite else { return false }
        if nativeFullscreen { return display.contains(CGPoint(x: window.midX, y: window.midY)) }
        return abs(window.minX - display.minX) <= 2 && abs(window.minY - display.minY) <= 2
            && abs(window.width - display.width) <= 2 && abs(window.height - display.height) <= 2
    }
}
