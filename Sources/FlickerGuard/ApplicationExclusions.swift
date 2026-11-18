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

struct BrowserPauseState {
    private var application: String?
    private var paused = false
    private var candidate: Bool?
    private var candidateSince: Date?

    func isPaused(for application: String) -> Bool { self.application == application && paused }

    mutating func reset() { self = Self() }

    mutating func observe(application: String, fullscreen: Bool?, at date: Date = Date()) -> Bool {
        if self.application != application {
            reset()
            self.application = application
        }
        guard let fullscreen, fullscreen != paused else {
            candidate = nil
            candidateSince = nil
            return paused
        }
        if candidate == fullscreen, let candidateSince, date.timeIntervalSince(candidateSince) >= 2 {
            paused = fullscreen
            candidate = nil
            self.candidateSince = nil
        } else if candidate != fullscreen {
            candidate = fullscreen
            candidateSince = date
        }
        return paused
    }
}

@MainActor
enum BrowserFullscreenReader {
    private static let browserIdentifiers = Set(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        .compactMap { Bundle(url: $0)?.bundleIdentifier })

    static func isBrowser(_ identifier: String) -> Bool {
        browserIdentifiers.contains(identifier)
    }

    nonisolated static func isFullscreen(pid: pid_t, displayID: CGDirectDisplayID) -> Bool? {
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
        guard let nativeFullscreen = values[2] as? Bool else { return nil }
        let frame = CGRect(origin: origin, size: dimensions)
        let display = CGDisplayBounds(displayID)
        guard matchesDisplay(window: frame, display: display, nativeFullscreen: nativeFullscreen, browserControlsVisible: false) == true else { return false }
        return matchesDisplay(window: frame, display: display, nativeFullscreen: nativeFullscreen,
                              browserControlsVisible: browserControlsVisible(in: window, frame: frame))
    }

    nonisolated private static func browserControlsVisible(in window: AXUIElement, frame: CGRect) -> Bool? {
        var queue = [window]
        var index = 0
        let deadline = Date().addingTimeInterval(0.12)
        let attributes = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, "AXHidden" as CFString] as CFArray
        while index < queue.count {
            guard index < 100, Date() < deadline, !Task.isCancelled else { return nil }
            let element = queue[index]
            index += 1
            AXUIElementSetMessagingTimeout(element, 0.02)
            var result: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &result) == .success,
                  let values = result as? [AnyObject], values.count == 4,
                  let role = values[0] as? String else { return nil }
            // Page contents are irrelevant; inspect only the browser's own controls.
            if role == "AXWebArea" || values[3] as? Bool == true { continue }
            if role == "AXToolbar" || role == "AXTabGroup" {
                var origin = CGPoint.zero
                var size = CGSize.zero
                guard CFGetTypeID(values[1]) == AXValueGetTypeID(), CFGetTypeID(values[2]) == AXValueGetTypeID(),
                      AXValueGetValue(values[1] as! AXValue, .cgPoint, &origin),
                      AXValueGetValue(values[2] as! AXValue, .cgSize, &size) else { return nil }
                let bounds = CGRect(origin: origin, size: size).intersection(frame)
                if bounds.isEmpty { continue }
                if bounds.height > 2, bounds.width > frame.width / 3, bounds.minY < frame.minY + 140 { return true }
            }
            var childrenValue: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            if status == .attributeUnsupported || status == .noValue { continue }
            guard status == .success, let children = childrenValue as? [AXUIElement],
                  queue.count + children.count <= 100 else { return nil }
            queue.append(contentsOf: children)
        }
        return false
    }

    nonisolated static func matchesDisplay(window: CGRect, display: CGRect, nativeFullscreen: Bool, browserControlsVisible: Bool?) -> Bool? {
        guard !window.isEmpty, !display.isEmpty,
              window.origin.x.isFinite, window.origin.y.isFinite,
              window.width.isFinite, window.height.isFinite, nativeFullscreen,
              display.contains(CGPoint(x: window.midX, y: window.midY)) else { return false }
        return browserControlsVisible.map { !$0 }
    }
}
