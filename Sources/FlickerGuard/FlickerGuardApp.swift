import AppKit
import Darwin
import SwiftUI
import ServiceManagement

@main
struct FlickerGuardApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var controller

    var body: some Scene {
        MenuBarExtra {
            DiagnosticView(state: controller.state)
        } label: {
            MenuBarIcon(state: controller.state)
        }
        .menuBarExtraStyle(.window)
        Settings {
            ApplicationExclusionsView(state: controller.state)
        }
    }
}

@MainActor
private struct MenuBarIcon: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(systemName: state.isActive ? "sun.max.fill" : "sun.max")
            .accessibilityLabel("FlickerGuard")
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var terminationSignals: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        state.installSafetyObservers()
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            terminationSignals.append(source)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.restoreOriginal() else {
            let alert = NSAlert()
            alert.messageText = tr("ui.restoreAlert")
            alert.informativeText = state.errorMessage ?? tr("ui.restoreHelp")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.removeSafetyObservers()
    }
}

@MainActor
private struct DiagnosticView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FlickerGuard").font(.headline)
                    Text(AppInfo.version).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(state.checkingForUpdates ? tr("ui.checkingUpdates") : tr("ui.checkUpdates"), systemImage: "arrow.down.circle") {
                        Task { await state.checkForUpdates() }
                    }
                    .disabled(state.checkingForUpdates)
                    Link(destination: AppInfo.documentationURL) {
                        Label(tr("ui.documentation"), systemImage: "book")
                    }
                    Link(destination: AppInfo.issuesURL) {
                        Label(tr("ui.reportIssue"), systemImage: "exclamationmark.bubble")
                    }
                    SettingsLink {
                        Label(tr("ui.applicationExclusions"), systemImage: "app.badge")
                    }
                    Divider()
                    Toggle(tr("ui.launchAtLogin"), isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                        .help(tr("ui.launchAtLoginHelp"))
                    if state.launchAtLoginStatus == .requiresApproval {
                        Button(tr("ui.loginApproval")) { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Divider()
                    Button(tr("ui.copy"), systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.report, forType: .string)
                    }
                    Divider()
                    Button(tr("ui.quit"), systemImage: "power") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("ui.more"))
                .accessibilityLabel(tr("ui.more"))
            }
            HStack(spacing: 6) {
                Circle().fill(state.isPausedForApplication ? Color.orange : state.isActive ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(state.needsRestoration && !state.isActive ? tr("ui.restoreRequired") : state.isTransitioning ? tr("ui.transitioning") : state.isPausedForApplication ? tr("ui.applicationPaused") : state.isResuming ? tr("ui.resuming") : state.isActive ? (state.isAttenuating ? tr("ui.active") : tr("ui.noDimming")) : tr("ui.inactive"))
                Spacer(minLength: 8)
                Text(state.diagnostic.isRecognizedOLED ? tr("ui.oledDetected") : tr("ui.oledUnavailable"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)

            if state.isPausedForApplication || state.isTransitioning {
                Text(state.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tr("ui.software")).font(.callout).foregroundStyle(.secondary)
                Text(state.softwareLevelText)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                Slider(value: Binding(get: { state.softwareLevel }, set: { state.setSoftwareLevel($0) }), in: BrightnessCurve.range, step: 0.01)
                    .disabled(!state.isActive)
                    .accessibilityLabel(tr("ui.software"))
                    .accessibilityValue(state.softwareLevelText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(tr("ui.automatic"), isOn: Binding(get: { state.automaticAdjustment }, set: { state.setAutomaticAdjustment($0) }))
                    .toggleStyle(.switch)
                    .disabled(state.needsRestoration && !state.isActive)
                Text(state.automaticAdjustment ? tr("ui.automaticHelp") : tr("ui.manualHelp"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.ambientLightText)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Label(tr("ui.hardware"), systemImage: "display").foregroundStyle(.secondary)
                Spacer()
                Text(state.hardwareLevelText)
                    .monospacedDigit()
                    .foregroundStyle(state.hardwareIsMaximum ? Color.green : Color.primary)
            }
            .font(.callout)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if let message = state.errorMessage ?? (!state.isActive && !state.isResuming ? state.activationProblem : nil) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if state.isActive || state.isResuming || state.needsRestoration { state.restoreOriginal() }
                else { state.activate() }
            } label: {
                Label(state.needsRestoration && !state.isActive ? tr("ui.restore") : state.isActive || state.isResuming ? tr("ui.disable") : tr("ui.enable"),
                      systemImage: state.needsRestoration && !state.isActive ? "arrow.counterclockwise" : state.isActive || state.isResuming ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!state.isActive && !state.isResuming && !state.needsRestoration && state.activationProblem != nil)

            if !state.hasKeyPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("ui.keyPermission")).foregroundStyle(.secondary)
                    Button(tr("ui.permissions")) { openAccessibilitySettings() }.buttonStyle(.link)
                    Link(tr("ui.installationHelp"), destination: AppInfo.documentationURL)
                }
                .font(.caption)
            } else if state.isActive {
                Label(tr("ui.keysActive"), systemImage: "keyboard")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { state.refreshLaunchAtLogin() }
        .alert(tr("ui.checkUpdates"), isPresented: Binding(
            get: { state.updateMessage != nil },
            set: { if !$0 { state.updateMessage = nil } }
        )) {
            if state.updateAvailable {
                Button(tr("ui.downloadUpdate")) { NSWorkspace.shared.open(AppInfo.downloadURL) }
            }
            Button(tr("ui.ok"), role: .cancel) { }
        } message: {
            Text(state.updateMessage ?? "")
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private struct ApplicationExclusionsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("ui.applicationExclusions")).font(.headline)
            Text(tr("ui.applicationExclusionsHelp"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(state.excludedApplications.keys.sorted {
                    (state.excludedApplications[$0] ?? $0).localizedStandardCompare(state.excludedApplications[$1] ?? $1) == .orderedAscending
                }, id: \.self) { identifier in
                    HStack {
                        Text(state.excludedApplications[identifier] ?? identifier)
                        Spacer()
                        Button {
                            state.removeExcludedApplication(identifier)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(tr("ui.removeExcludedApplication", ["app": state.excludedApplications[identifier] ?? identifier]))
                    }
                }
            }
            .overlay {
                if state.excludedApplications.isEmpty {
                    Text(tr("ui.noExcludedApplications")).foregroundStyle(.secondary)
                }
            }
            Button(tr("ui.addExcludedApplications"), systemImage: "plus") {
                Task { await state.chooseExcludedApplications() }
            }
            Toggle(tr("ui.pauseBrowserFullscreen"), isOn: Binding(get: { state.pauseBrowserFullscreen }, set: { state.setPauseBrowserFullscreen($0) }))
            Text(tr("ui.pauseBrowserFullscreenHelp"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = state.exclusionErrorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 480, height: 430)
        .onAppear { NSApplication.shared.activate() }
    }
}
