import AppKit
import Darwin
import SwiftUI
import ServiceManagement

@main
struct FlickerGuardApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var controller

    var body: some Scene {
        MenuBarExtra("FlickerGuard", systemImage: "sun.max") {
            DiagnosticView(state: controller.state)
        }
        .menuBarExtraStyle(.window)
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
                Image(systemName: "sun.max.fill")
                    .accessibilityHidden(true)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("FlickerGuard").font(.headline)
                    Text(AppInfo.version).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(tr("ui.refresh"), systemImage: "arrow.clockwise") { state.refresh() }
                    Button(tr("ui.copy"), systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.report, forType: .string)
                    }
                    Button(tr("ui.restore"), systemImage: "arrow.counterclockwise") { state.restoreOriginal() }
                        .disabled(!state.needsRestoration)
                    Button(tr("ui.permissions"), systemImage: "lock.shield") { openAccessibilitySettings() }
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
                Circle().fill(state.isActive ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(state.needsRestoration && !state.isActive ? tr("ui.restoreRequired") : state.isResuming ? tr("ui.resuming") : state.isActive ? (state.isAttenuating ? tr("ui.active") : tr("ui.noDimming")) : tr("ui.inactive"))
                Spacer(minLength: 8)
                Text(state.diagnostic.isRecognizedOLED ? tr("ui.oledDetected") : tr("ui.oledUnavailable"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .accessibilityElement(children: .combine)

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
                Toggle(tr("ui.launchAtLogin"), isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                if state.launchAtLoginStatus == .requiresApproval {
                    Button(tr("ui.loginApproval")) { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
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
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
