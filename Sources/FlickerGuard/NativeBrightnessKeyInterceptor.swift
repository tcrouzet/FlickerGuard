import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hidsystem

enum BrightnessKeyAction: Equatable, Sendable {
    case increase, decrease, release, unsupported

    static func decode(subtype: Int16, data1: Int) -> BrightnessKeyAction? {
        guard subtype == NX_SUBTYPE_AUX_CONTROL_BUTTONS else { return nil }
        let key = (data1 >> 16) & 0xFFFF
        guard key == NX_KEYTYPE_BRIGHTNESS_UP || key == NX_KEYTYPE_BRIGHTNESS_DOWN else { return nil }
        switch (data1 >> 8) & 0xFF {
        case Int(NX_KEYDOWN): return key == NX_KEYTYPE_BRIGHTNESS_UP ? .increase : .decrease
        case Int(NX_KEYUP): return .release
        default: return .unsupported
        }
    }

    func level(from current: Double) -> Double? {
        switch self {
        case .increase: min(1, current + 1.0 / 16)
        case .decrease: max(BrightnessCurve.minimumLevel, current - 1.0 / 16)
        case .release, .unsupported: nil
        }
    }
}

enum BrightnessKeyError: LocalizedError {
    case permissionRequired, unavailable, disabled, unsupportedEvent

    var errorDescription: String? {
        switch self {
        case .permissionRequired: tr("error.keyPermission")
        case .unavailable: tr("error.keyUnavailable")
        case .disabled: tr("error.keyDisabled")
        case .unsupportedEvent: tr("error.keyEvent")
        }
    }
}

@MainActor
final class NativeBrightnessKeyInterceptor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onKey: ((BrightnessKeyAction) -> Void)?
    private var onFailure: ((BrightnessKeyError) -> Void)?

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var hasPermission: Bool { AXIsProcessTrusted() }

    func start(onKey: @escaping (BrightnessKeyAction) -> Void, onFailure: @escaping (BrightnessKeyError) -> Void) throws {
        guard !isRunning else { return }
        stop()
        // The SDK declares the option key as mutable; its CFString value is stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw BrightnessKeyError.permissionRequired }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue,
            callback: Self.callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw BrightnessKeyError.unavailable }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            CFMachPortInvalidate(port)
            throw BrightnessKeyError.unavailable
        }
        self.onKey = onKey
        self.onFailure = onFailure
        tap = port
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard isRunning else {
            stop()
            throw BrightnessKeyError.unavailable
        }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        onKey = nil
        onFailure = nil
    }

    nonisolated private static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let decoded: Result<BrightnessKeyAction, BrightnessKeyError>
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            decoded = .failure(.disabled)
        } else {
            guard type.rawValue == NSEvent.EventType.systemDefined.rawValue else { return Unmanaged.passUnretained(event) }
            if let cocoaEvent = NSEvent(cgEvent: event) {
                guard let action = BrightnessKeyAction.decode(subtype: cocoaEvent.subtype.rawValue, data1: cocoaEvent.data1) else {
                    return Unmanaged.passUnretained(event)
                }
                decoded = .success(action)
            } else {
                decoded = .failure(.unsupportedEvent)
            }
        }
        let interceptor = Unmanaged<NativeBrightnessKeyInterceptor>.fromOpaque(context).takeUnretainedValue()
        // The tap source is installed only on the main run loop.
        MainActor.assumeIsolated {
            switch decoded {
            case .success(let action):
                switch action {
                case .increase, .decrease: interceptor.onKey?(action)
                case .release: break
                case .unsupported: interceptor.onFailure?(.unsupportedEvent)
                }
            case .failure(let error): interceptor.onFailure?(error)
            }
        }
        return nil
    }
}
