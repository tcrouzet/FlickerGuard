import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var diagnostic = DisplayDiagnostic.capture()
    @Published private(set) var isActive = false
    @Published private var settings = SoftwareBrightnessSettings()
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchAtLoginStatus = SMAppService.Status.notRegistered
    @Published private(set) var checkingForUpdates = false
    @Published private(set) var updateAvailable = false
    @Published var updateMessage: String?
    @Published private var applicationExclusions = ApplicationExclusions(
        applications: UserDefaults.standard.dictionary(forKey: "excludedApplications") as? [String: String] ?? [:],
        browserFullscreen: UserDefaults.standard.bool(forKey: "pauseBrowserFullscreen")
    )
    @Published private(set) var excludedApplicationName: String?
    @Published private(set) var exclusionErrorMessage: String?
    @Published private var resumeState = DisplayResumeState()
    @Published private var tableCorrectionCount = 0

    nonisolated let transfer = DisplayTransferController()
    private var pendingUpdate: Task<Void, Never>?
    private var hardwareMonitor: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private let brightnessKeys = NativeBrightnessKeyInterceptor()
    private var ambientCurve: AmbientBrightness?
    private var ambientDiagnostic = AmbientBrightnessDiagnostic()
    private var appliedSoftwareLevel: Double?
    private var lidWasClosed = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastExternalApplication: NSRunningApplication?
    private var lastContextBundleIdentifier: String?
    private var lastApplicationContextRead = Date.distantPast
    @Published private var configurationObserverInstalled = false

    var softwareLevel: Double { settings.level }
    var automaticAdjustment: Bool { settings.automatic }
    var isResuming: Bool { resumeState.pending }
    var isPausedForApplication: Bool { resumeState.pending && resumeState.applicationBlocked }
    var excludedApplications: [String: String] { applicationExclusions.applications }
    var pauseBrowserFullscreen: Bool { applicationExclusions.browserFullscreen }
    var launchAtLogin: Bool { launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval }
    var isAttenuating: Bool { isActive && softwareLevel < 1 }
    var needsRestoration: Bool { transfer.needsRestoration }
    var hasKeyPermission: Bool { brightnessKeys.hasPermission }
    var softwareLevelText: String { softwareLevel.formatted(.percent.precision(.fractionLength(0))) }
    var ambientLightText: String {
        guard isActive, automaticAdjustment else { return tr("ui.ambientInactive") }
        guard let lux = ambientDiagnostic.measuredLux else { return tr("report.ambientWaiting") }
        return tr("report.ambientLux", ["value": lux.formatted(.number.precision(.fractionLength(1)))])
    }
    var hardwareLevelText: String {
        guard let brightness = try? diagnostic.hardwareBrightness?.get() else { return tr("common.unavailable") }
        return brightness.level.formatted(.percent.precision(.fractionLength(0)))
    }
    var hardwareIsMaximum: Bool { (try? diagnostic.hardwareBrightness?.get().level) == 1 }

    var activationProblem: String? {
        guard configurationObserverInstalled else { return tr("error.observerUnavailable") }
        guard !needsRestoration else { return DimmingError.restorationRequired.localizedDescription }
        if let excludedApplicationName { return tr("error.applicationExcluded", ["app": excludedApplicationName]) }
        do {
            _ = try DimmingEligibility.validate(diagnostic)
            return nil
        } catch { return error.localizedDescription }
    }

    var status: String {
        if needsRestoration && !isActive { return tr("status.restore") }
        if isPausedForApplication { return tr("status.applicationPaused", ["app": excludedApplicationName ?? ""]) }
        if isResuming { return tr("status.resuming") }
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
         tr("report.tableCorrections", ["count": tableCorrectionCount.formatted()]),
         tr("report.applicationExclusions", ["count": excludedApplications.count.formatted()]),
         tr("report.browserFullscreen", ["value": pauseBrowserFullscreen ? tr("ui.on") : tr("ui.off")]),
         errorMessage.map { tr("report.error", ["error": $0]) }].compactMap { $0 } + automatic).joined(separator: "\n")
    }

    func checkForUpdates() async {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        updateAvailable = false
        defer { checkingForUpdates = false }
        do {
            let latest = try await UpdateChecker.latestVersion()
            updateAvailable = try UpdateChecker.isNewer(latest, than: AppInfo.version)
            updateMessage = updateAvailable
                ? tr("ui.updateAvailable", ["version": latest, "current": AppInfo.version])
                : tr("ui.upToDate", ["version": AppInfo.version])
        } catch {
            updateMessage = tr("ui.updateFailed", ["error": error.localizedDescription])
        }
    }

    func installSafetyObservers() {
        let result = CGDisplayRegisterReconfigurationCallback(
            Self.displayConfigurationChanged, Unmanaged.passUnretained(self).toOpaque()
        )
        configurationObserverInstalled = result == .success
        if result != .success { errorMessage = DimmingError.configurationObserver(result.rawValue).localizedDescription }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshApplicationExclusion() }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendForInterruption(sleeping: true) }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard LidStateReader.isClosed() != true else { return }
                    self.resumeState.wake()
                    self.refresh()
                    self.scheduleResume()
                }
            })
        }
        refresh()
        refreshLaunchAtLogin()
        refreshApplicationExclusion()
        startHardwareMonitor()
    }

    func removeSafetyObservers() {
        resumeTask?.cancel()
        resumeTask = nil
        resumeState.cancel()
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
        guard configurationObserverInstalled, !resumeState.sleeping, LidStateReader.isClosed() != true, !isActive, !needsRestoration else { return }
        refreshApplicationExclusion()
        guard !resumeState.applicationBlocked else { return }
        let resuming = resumeState.pending
        resumeState.cancel()
        errorMessage = nil
        diagnostic = .capture()
        do {
            _ = try DimmingEligibility.validate(diagnostic)
            guard let hardware = try diagnostic.hardwareBrightness?.get() else { throw HardwareBrightnessError.unavailableAPI }
            let lux = automaticAdjustment && !resuming ? try AmbientLightReader.read() : nil
            let level = try settings.activationLevel(hardware: hardware, ambientLux: lux, resuming: resuming)
            let curve = automaticAdjustment ? AmbientBrightness() : nil
            var readings = AmbientBrightnessDiagnostic()
            if resuming { try readings.retainLevel(level) }
            if let lux, let curve { _ = try readings.observe(lux: lux, curve: curve, current: level) }
            try brightnessKeys.start(onKey: { [weak self] action in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive, let level = action.level(from: self.softwareLevel) else { return }
                    self.setSoftwareLevel(level, debounce: false)
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    self.stopAfterError(error)
                }
            })
            try transfer.prepare(diagnostic, level: level)
            try settings.remember(level)
            if automaticAdjustment { readings.didAdjust() }
            ambientCurve = curve
            ambientDiagnostic = readings
            appliedSoftwareLevel = level
            isActive = true
            if resuming { resumeState.didResume() }
            tableCorrectionCount = 0
            diagnostic = .capture()
        } catch { stopAfterError(error) }
    }

    func setSoftwareLevel(_ level: Double, debounce: Bool = true) {
        guard isActive else { return }
        guard level.isFinite, BrightnessCurve.range.contains(level) else {
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
            let lux = enabled && isActive && resumeState.canReadAmbient() && LidStateReader.isClosed() != true ? try AmbientLightReader.read() : nil
            let curve = enabled && isActive ? AmbientBrightness() : nil
            var readings = AmbientBrightnessDiagnostic()
            let next: Double?
            if let lux, let curve { next = try readings.observe(lux: lux, curve: curve, current: softwareLevel) }
            else {
                if curve != nil { try readings.retainLevel(softwareLevel) }
                next = nil
            }
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
        guard automaticAdjustment, let ambientCurve, resumeState.canReadAmbient(), LidStateReader.isClosed() != true else { return }
        let level = try ambientDiagnostic.observe(lux: AmbientLightReader.read(), curve: ambientCurve, current: softwareLevel)
        guard level != softwareLevel else { return }
        pendingUpdate?.cancel()
        try settings.remember(level)
        if applySoftwareLevel(level) { ambientDiagnostic.didAdjust() }
    }

    @discardableResult
    func restoreOriginal() -> Bool {
        resumeTask?.cancel()
        resumeTask = nil
        resumeState.cancel()
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

    private func suspendForInterruption(sleeping: Bool) {
        let wasActive = isActive || resumeState.pending
        _ = restoreOriginal()
        resumeState.interrupt(wasActive: wasActive, sleeping: sleeping)
        if !sleeping { scheduleResume() }
    }

    private func scheduleResume() {
        guard resumeState.shouldResume else { return }
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            for _ in 0..<20 {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, !Task.isCancelled, self.resumeState.shouldResume else { return }
                do {
                    if self.needsRestoration {
                        try self.transfer.restore()
                        self.brightnessKeys.stop()
                    }
                    self.diagnostic = .capture()
                    guard (try? DimmingEligibility.validate(self.diagnostic)) != nil else { continue }
                    self.activate()
                    return
                } catch { self.errorMessage = error.localizedDescription }
            }
            guard let self, !Task.isCancelled, self.resumeState.pending else { return }
            self.resumeState.cancel()
            self.errorMessage = tr("error.resumeUnavailable")
        }
    }

    func refreshLaunchAtLogin() { launchAtLoginStatus = SMAppService.mainApp.status }

    func chooseExcludedApplications() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard await panel.begin() == .OK else { return }
        exclusionErrorMessage = nil
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
                  !identifier.isEmpty, identifier != "com.tcrouzet.FlickerGuard" else {
                exclusionErrorMessage = tr("error.excludedApplication", ["app": url.lastPathComponent])
                continue
            }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            applicationExclusions.applications[identifier] = name
        }
        UserDefaults.standard.set(applicationExclusions.applications, forKey: "excludedApplications")
        refreshApplicationExclusion()
    }

    func removeExcludedApplication(_ identifier: String) {
        applicationExclusions.applications.removeValue(forKey: identifier)
        UserDefaults.standard.set(applicationExclusions.applications, forKey: "excludedApplications")
        exclusionErrorMessage = nil
        refreshApplicationExclusion()
    }

    func setPauseBrowserFullscreen(_ enabled: Bool) {
        applicationExclusions.browserFullscreen = enabled
        UserDefaults.standard.set(enabled, forKey: "pauseBrowserFullscreen")
        refreshApplicationExclusion()
    }

    private func refreshApplicationExclusion() {
        lastApplicationContextRead = Date()
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != "com.tcrouzet.FlickerGuard" {
            lastExternalApplication = frontmost
        }
        guard let application = lastExternalApplication, let identifier = application.bundleIdentifier else { return }
        var fullscreen: Bool? = false
        if pauseBrowserFullscreen, excludedApplications[identifier] == nil,
           BrowserFullscreenReader.isBrowser(identifier), let display = diagnostic.display {
            fullscreen = BrowserFullscreenReader.isFullscreen(pid: application.processIdentifier, displayID: display.displayID)
        }
        let decision = applicationExclusions.shouldPause(bundleIdentifier: identifier, browserIsFullscreen: fullscreen)
        if decision == nil && lastContextBundleIdentifier == identifier { return }
        lastContextBundleIdentifier = identifier
        let blocked = decision == true
        let wasBlocked = resumeState.applicationBlocked
        excludedApplicationName = blocked ? (excludedApplications[identifier] ?? application.localizedName ?? identifier) : nil
        resumeState.setApplicationBlocked(blocked)
        if blocked && isActive {
            suspendForInterruption(sleeping: false)
        } else if wasBlocked && !blocked {
            scheduleResume()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        defer { refreshLaunchAtLogin() }
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status != .notRegistered { try service.unregister() }
            errorMessage = nil
        } catch { errorMessage = tr("error.launchAtLogin", ["error": error.localizedDescription]) }
    }

    private func checkActiveDisplay() throws -> HardwareBrightness {
        guard brightnessKeys.isRunning else { throw BrightnessKeyError.disabled }
        let brightness = try transfer.checkHardwareBrightness()
        if let appliedSoftwareLevel, try transfer.ensureSoftwareLevel(appliedSoftwareLevel) {
            tableCorrectionCount += 1
        }
        return brightness
    }

    func refresh() {
        if isActive {
            do {
                _ = try checkActiveDisplay()
            } catch { stopAfterError(error) }
        }
        diagnostic = .capture()
    }

    private func stopAfterError(_ error: Error) {
        if isActive && transfer.isReconfiguring {
            suspendForInterruption(sleeping: false)
            return
        }
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
                if let closed = LidStateReader.isClosed() {
                    if closed {
                        self.lidWasClosed = true
                        if self.isActive || (self.resumeState.pending && !self.resumeState.sleeping) {
                            self.suspendForInterruption(sleeping: true)
                        }
                        continue
                    } else if self.lidWasClosed {
                        self.lidWasClosed = false
                        self.resumeState.wake()
                        self.scheduleResume()
                    }
                }
                do {
                    if Date().timeIntervalSince(self.lastApplicationContextRead) >= 1 {
                        self.refreshApplicationExclusion()
                    }
                    let brightness: HardwareBrightness
                    if self.isActive {
                        brightness = try self.checkActiveDisplay()
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
                switch result {
                case .success:
                    state.suspendForInterruption(sleeping: false)
                case .failure(let error):
                    state.stopAfterError(error)
                }
            }
        } else if !flags.intersection([.setModeFlag, .addFlag, .removeFlag, .enabledFlag, .disabledFlag]).isEmpty {
            Task { @MainActor in
                state.refresh()
                state.scheduleResume()
            }
        }
    }
}
