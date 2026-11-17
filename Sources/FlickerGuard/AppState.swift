import AppKit
import Combine
import CoreGraphics

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var diagnostic = DisplayDiagnostic.capture()
    @Published private(set) var isActive = false
    @Published private var settings = SoftwareBrightnessSettings()
    @Published private(set) var errorMessage: String?

    nonisolated let transfer = DisplayTransferController()
    private var pendingUpdate: Task<Void, Never>?
    private var hardwareMonitor: Task<Void, Never>?
    private let brightnessKeys = NativeBrightnessKeyInterceptor()
    private var ambientCurve: AmbientBrightness?
    private var ambientDiagnostic = AmbientBrightnessDiagnostic()
    private var appliedSoftwareLevel: Double?
    private var workspaceObservers: [NSObjectProtocol] = []
    @Published private var configurationObserverInstalled = false

    var softwareLevel: Double { settings.level }
    var automaticAdjustment: Bool { settings.automatic }
    var isAttenuating: Bool { isActive && softwareLevel < 1 }
    var needsRestoration: Bool { transfer.needsRestoration }
    var hasKeyPermission: Bool { brightnessKeys.hasPermission }
    var softwareLevelText: String { softwareLevel.formatted(.percent.precision(.fractionLength(0))) }
    var hardwareLevelText: String {
        guard let brightness = try? diagnostic.hardwareBrightness?.get() else { return tr("common.unavailable") }
        return brightness.level.formatted(.percent.precision(.fractionLength(0)))
    }
    var hardwareIsMaximum: Bool { (try? diagnostic.hardwareBrightness?.get().level) == 1 }

    var activationProblem: String? {
        guard configurationObserverInstalled else { return tr("error.observerUnavailable") }
        guard !needsRestoration else { return DimmingError.restorationRequired.localizedDescription }
        do {
            _ = try DimmingEligibility.validate(diagnostic)
            return nil
        } catch { return error.localizedDescription }
    }

    var status: String {
        if needsRestoration && !isActive { return tr("status.restore") }
        if isActive && !isAttenuating { return tr("status.noDimming") }
        return isActive ? tr("status.active") : tr("status.inactive")
    }

    var report: String {
        let applied = appliedSoftwareLevel.map { $0.formatted(.percent.precision(.fractionLength(2))) } ?? tr("common.unavailable")
        let automatic = automaticAdjustment ? (isActive ? ambientDiagnostic.report() : [tr("report.ambientInactive")]) : []
        return ([diagnostic.report, "FlickerGuard \(AppInfo.version)", tr("report.status", ["status": status]),
         tr("report.software", ["level": softwareLevelText]),
         tr("report.softwareApplied", ["level": applied]),
         tr("report.automatic", ["value": automaticAdjustment ? tr("ui.on") : tr("ui.off")]),
         errorMessage.map { tr("report.error", ["error": $0]) }].compactMap { $0 } + automatic).joined(separator: "\n")
    }

    func installSafetyObservers() {
        let result = CGDisplayRegisterReconfigurationCallback(
            Self.displayConfigurationChanged, Unmanaged.passUnretained(self).toOpaque()
        )
        configurationObserverInstalled = result == .success
        if result != .success { errorMessage = DimmingError.configurationObserver(result.rawValue).localizedDescription }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.restoreOriginal() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.restoreOriginal()
                    self.refresh()
                }
            })
        }
        refresh()
        startHardwareMonitor()
    }

    func removeSafetyObservers() {
        brightnessKeys.stop()
        hardwareMonitor?.cancel()
        hardwareMonitor = nil
        if configurationObserverInstalled {
            CGDisplayRemoveReconfigurationCallback(Self.displayConfigurationChanged, Unmanaged.passUnretained(self).toOpaque())
            configurationObserverInstalled = false
        }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    func activate() {
        guard configurationObserverInstalled, !isActive, !needsRestoration else { return }
        errorMessage = nil
        diagnostic = .capture()
        do {
            _ = try DimmingEligibility.validate(diagnostic)
            guard let hardware = try diagnostic.hardwareBrightness?.get() else { throw HardwareBrightnessError.unavailableAPI }
            let lux = automaticAdjustment ? try AmbientLightReader.read() : nil
            let level = try settings.activationLevel(hardware: hardware, ambientLux: lux)
            let curve = automaticAdjustment ? AmbientBrightness() : nil
            var readings = AmbientBrightnessDiagnostic()
            if let lux, let curve { _ = try readings.observe(lux: lux, curve: curve, current: level) }
            try brightnessKeys.start(onKey: { [weak self] action in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive, let level = action.level(from: self.softwareLevel) else { return }
                    self.setSoftwareLevel(level, debounce: false)
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor [weak self] in self?.stopAfterError(error) }
            })
            try transfer.prepare(diagnostic, level: level)
            try settings.remember(level)
            if automaticAdjustment { readings.didAdjust() }
            ambientCurve = curve
            ambientDiagnostic = readings
            appliedSoftwareLevel = level
            isActive = true
            diagnostic = .capture()
        } catch { stopAfterError(error) }
    }

    func setSoftwareLevel(_ level: Double, debounce: Bool = true) {
        guard isActive else { return }
        guard level.isFinite, (0.1...1).contains(level) else {
            stopAfterError(DimmingError.invalidLevel)
            return
        }
        do {
            try settings.selectManual(level)
            ambientCurve = nil
            ambientDiagnostic = AmbientBrightnessDiagnostic()
            errorMessage = nil
        } catch {
            stopAfterError(error)
            return
        }
        pendingUpdate?.cancel()
        pendingUpdate = nil
        guard appliedSoftwareLevel != level else { return }
        if !debounce {
            applySoftwareLevel(level)
            return
        }
        pendingUpdate = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.applySoftwareLevel(level)
        }
    }

    @discardableResult
    private func applySoftwareLevel(_ level: Double) -> Bool {
        do {
            guard brightnessKeys.isRunning else { throw BrightnessKeyError.disabled }
            try transfer.apply(level: level)
            appliedSoftwareLevel = level
            return true
        } catch {
            stopAfterError(error)
            return false
        }
    }

    func setAutomaticAdjustment(_ enabled: Bool) {
        do {
            let lux = enabled && isActive ? try AmbientLightReader.read() : nil
            let curve = enabled && isActive ? AmbientBrightness() : nil
            var readings = AmbientBrightnessDiagnostic()
            let next: Double?
            if let lux, let curve { next = try readings.observe(lux: lux, curve: curve, current: softwareLevel) }
            else { next = nil }
            ambientCurve = curve
            ambientDiagnostic = readings
            settings.automatic = enabled
            errorMessage = nil
            if let next, next != softwareLevel {
                pendingUpdate?.cancel()
                try settings.remember(next)
                if applySoftwareLevel(next) { ambientDiagnostic.didAdjust() }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func followAmbientLight() throws {
        guard automaticAdjustment, let ambientCurve else { return }
        let level = try ambientDiagnostic.observe(lux: AmbientLightReader.read(), curve: ambientCurve, current: softwareLevel)
        guard level != softwareLevel else { return }
        pendingUpdate?.cancel()
        try settings.remember(level)
        if applySoftwareLevel(level) { ambientDiagnostic.didAdjust() }
    }

    @discardableResult
    func restoreOriginal() -> Bool {
        cancelUpdates()
        isActive = false
        ambientCurve = nil
        let hadBackup = needsRestoration
        do {
            try transfer.restore()
            if hadBackup { appliedSoftwareLevel = 1 }
            brightnessKeys.stop()
            errorMessage = nil
            diagnostic = .capture()
            return true
        } catch {
            errorMessage = tr("error.restore", ["error": error.localizedDescription])
            return false
        }
    }

    func refresh() {
        if isActive {
            do {
                guard brightnessKeys.isRunning else { throw BrightnessKeyError.disabled }
                try transfer.checkHardwareBrightness()
            } catch { stopAfterError(error) }
        }
        diagnostic = .capture()
    }

    private func stopAfterError(_ error: Error) {
        let message = error.localizedDescription
        if restoreOriginal() { errorMessage = message }
        else { errorMessage = message + "\n" + (errorMessage ?? "") }
        diagnostic = .capture()
    }

    private func cancelUpdates() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
    }

    private func startHardwareMonitor() {
        hardwareMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                do {
                    let brightness: HardwareBrightness
                    if self.isActive {
                        guard self.brightnessKeys.isRunning else { throw BrightnessKeyError.disabled }
                        brightness = try self.transfer.checkHardwareBrightness()
                    } else if let display = self.diagnostic.display {
                        brightness = try HardwareBrightnessReader.read(displayID: display.displayID)
                    } else { continue }
                    self.diagnostic.hardwareBrightness = .success(brightness)
                    if self.isActive { try self.followAmbientLight() }
                } catch {
                    if self.isActive { self.stopAfterError(error) }
                    else { self.diagnostic.hardwareBrightness = .failure(error) }
                }
            }
        }
    }

    nonisolated private static let displayConfigurationChanged: CGDisplayReconfigurationCallBack = { displayID, flags, context in
        guard let context else { return }
        let state = Unmanaged<AppState>.fromOpaque(context).takeUnretainedValue()
        if flags.contains(.beginConfigurationFlag),
           let result = state.transfer.restoreBeforeReconfiguration(displayID: displayID) {
            Task { @MainActor in
                state.cancelUpdates()
                state.isActive = false
                switch result {
                case .success:
                    if state.restoreOriginal() { state.errorMessage = tr("error.configurationRestored") }
                case .failure(let error):
                    state.errorMessage = tr("error.configurationRestore", ["error": error.localizedDescription])
                }
            }
        } else if !flags.intersection([.setModeFlag, .addFlag, .removeFlag, .enabledFlag, .disabledFlag]).isEmpty {
            Task { @MainActor in state.refresh() }
        }
    }
}
