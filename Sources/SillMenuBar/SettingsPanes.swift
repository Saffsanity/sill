import AppKit
import Combine
import SwiftUI
import SillHostCore
import StreamProtocol

/// One Settings tab: a grouped Form, 520 pt wide. The controls bind straight to
/// `settings.config`, whose didSet is the one path to the host (see HostSettings).
struct SettingsPane: View {
    let tab: SettingsTab
    let model: AppModel

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralPane(model: model)
            case .streaming: StreamingPane(model: model, settings: model.settings)
            case .virtualDisplay: VirtualDisplayPane(model: model, settings: model.settings)
            case .permissions: PermissionsPane(model: model)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        // Permissions and the login item change behind Sill's back, in System Settings. Re-read
        // them once a second, only while this tab is on screen, and when Sill becomes active; an
        // idle Sill with Settings closed wakes for nothing.
        .task(id: model.visibleSettingsTab == tab) {
            guard model.visibleSettingsTab == tab, tab != .streaming else { return }
            while !Task.isCancelled {
                model.permissions.refresh()
                model.loginItem.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissions.refresh()
            model.loginItem.refresh()
        }
    }
}

/// Footer text the way System Settings sets it: small, secondary, from the leading edge.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: General

private struct GeneralPane: View {
    let model: AppModel

    private static let runsFromApplications = Bundle.main.bundlePath.hasPrefix("/Applications/")

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.loginItem.isOn }, set: { model.loginItem.set($0) }))
                    .disabled(!model.loginItem.available)
                if !model.loginItem.available {
                    Footnote("Available when Sill runs from its app bundle.")
                } else if model.loginItem.needsApproval {
                    LabeledContent("Waiting for your approval") {
                        Button("Approve in System Settings…") { model.loginItem.openSystemSettings() }
                    }
                }
                if let error = model.loginItem.error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Running from") {
                    Text(Bundle.main.bundlePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if !Self.runsFromApplications {
                    Label("The login item and the permissions follow this copy of Sill. Keep one copy, in Applications.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                LabeledContent("Visible on your network as") { Text(networkName) }
            } footer: {
                HStack(spacing: 4) {
                    Text("This is the Mac’s name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Change It in Sharing Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.footnote)
                    Spacer(minLength: 0)
                }
            }
            Section {
                HStack {
                    Button("Show Log…") { model.showLog?() }
                    Button("Reveal Log File") {
                        if let url = HostLog.shared.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .disabled(HostLog.shared.fileURL == nil)
                }
            }
            Section {
                // A way out when the status item is hidden (a crowded menu bar, the notch).
                Button("Quit Sill") { NSApp.terminate(nil) }
            } footer: {
                Footnote("Sill \(AppModel.version) (\(AppModel.build)). Free and open source.")
            }
        }
    }

    private var networkName: String {
        let snapshot = model.coordinator?.status.snapshot ?? HostStatusSnapshot()
        switch snapshot.network {
        case .advertising(let name): return "“\(name)”"
        case .notAdvertised: return "Not advertised (test pattern mode)"
        case .failed: return "Not visible (the listener failed)"
        case .waiting: return "Not yet (waiting for the network)"
        case .starting, .registering: return "Registering…"
        }
    }
}

// MARK: Streaming

private struct StreamingPane: View {
    let model: AppModel
    @Bindable var settings: HostSettings

    var body: some View {
        Form {
            Section {
                Picker("Frame rate limit", selection: $settings.config.maxFPS) {
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                .pickerStyle(.segmented)
                Picker("Quality", selection: $settings.config.bitrate) {
                    ForEach(QualityPreset.allCases) { Text($0.title).tag($0.rawValue) }
                    if QualityPreset(rawValue: settings.config.bitrate) == nil {
                        Text(QualityPreset.title(forBitrate: settings.config.bitrate)).tag(settings.config.bitrate)
                    }
                }
                Picker("Resolution", selection: $settings.config.captureScale) {
                    Text("Retina").tag(CGFloat(2))
                    Text("Standard").tag(CGFloat(1))
                }
            } footer: {
                Footnote("Each device asks for its own screen’s rate, up to this limit. Quality is per 60 fps; a 120 fps stream gets twice as much. Changes apply at once: the current stream restarts for a moment.")
            }
            Section {
                Toggle("Prioritize encoding speed", isOn: $settings.config.prioritizeSpeed)
            } footer: {
                Footnote("Lower latency when the Mac is busy, at a softer picture.")
            }
            if model.coordinator?.status.snapshot.softwareEncoder == true {
                Section {
                    Label("The hardware encoder isn’t responding, so streams are limited to 60 fps at Standard resolution until the Mac restarts.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: Virtual Display

private struct VirtualDisplayPane: View {
    let model: AppModel
    @Bindable var settings: HostSettings
    @State private var retrying = false

    var body: some View {
        let snapshot = model.coordinator?.status.snapshot ?? HostStatusSnapshot()
        Form {
            Section {
                Toggle("Stream from a virtual display", isOn: $settings.config.virtualDisplay)
            } footer: {
                Footnote("Sill moves the window you pick onto an invisible display made for your device, so it keeps updating when other windows cover it and text is drawn at your device’s scale. The window leaves this screen while it streams and comes back when you stop streaming or quit Sill.")
            }
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        Text(statusText(snapshot))
                            .multilineTextAlignment(.trailing)
                        if canRetry(snapshot) {
                            Button("Try Again") {
                                retrying = true
                                Task { @MainActor in
                                    await model.coordinator?.retryVirtualDisplay()
                                    retrying = false
                                }
                            }
                            .disabled(retrying || model.coordinator == nil)
                        }
                    }
                }
                if settings.config.virtualDisplay, let failure = snapshot.lastStageFailure {
                    LabeledContent("Last window") {
                        Text("Streamed where it is: \(failure)").multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Footnote("Uses a private macOS interface (CGVirtualDisplay). If a macOS update breaks it, Sill streams the window where it is.")
            }
        }
    }

    private func statusText(_ s: HostStatusSnapshot) -> String {
        let sr = model.permissions.screenRecording, ax = model.permissions.accessibility
        if s.virtualDisplayAPIMissing, let problem = s.virtualDisplayProblem {
            return "Not available on this version of macOS: \(problem)"
        }
        if !sr && !ax { return "Needs Screen Recording and Accessibility" }
        if !ax { return "Needs Accessibility" }
        if !sr { return "Needs Screen Recording" }
        if let problem = s.virtualDisplayProblem { return "Off for this session: \(problem)" }
        return "Available"
    }

    /// A run-level disable (the system removed the display too often) can be retried; a missing
    /// API or permission cannot.
    private func canRetry(_ s: HostStatusSnapshot) -> Bool {
        s.virtualDisplayProblem != nil && !s.virtualDisplayAPIMissing && model.permissions.allGranted
    }
}

// MARK: Permissions

private struct PermissionsPane: View {
    let model: AppModel

    var body: some View {
        let permissions = model.permissions
        let network = model.coordinator?.status.snapshot.network
        Form {
            Section {
                PermissionRow(title: "Screen Recording", allowed: permissions.screenRecording,
                              explanation: "Lets Sill capture the windows you pick on your iPhone or iPad. Nothing is recorded or saved; frames go straight to your devices on this network.",
                              button: model.settings.askedScreenRecording ? "Open System Settings…" : "Allow…") {
                    permissions.requestScreenRecording()
                }
                PermissionRow(title: "Accessibility", allowed: permissions.accessibility,
                              explanation: "Lets your iPhone or iPad click, scroll and type on this Mac, and lets Sill move and size the window it streams.",
                              button: model.settings.askedAccessibility ? "Open System Settings…" : "Allow…") {
                    permissions.requestAccessibility()
                }
            } footer: {
                Footnote("Access belongs to Sill itself. Access you gave Terminal for the SillHost command-line tool doesn’t carry over.")
            }
            if permissions.relaunchSuggested, !permissions.screenRecording {
                Section {
                    LabeledContent("Screen Recording starts working once Sill opens again.") {
                        Button(permissions.canRelaunch ? "Relaunch Sill" : "Quit Sill") { permissions.relaunch() }
                    }
                }
            }
            if Self.networkNeedsHelp(network) {
                Section {
                    LabeledContent {
                        Button("Open Local Network…") { permissions.openPrivacyPane("Privacy_LocalNetwork") }
                    } label: {
                        Text("Local Network")
                        Text("If your iPhone or iPad can’t find this Mac, allow Sill in Privacy & Security › Local Network.")
                    }
                }
            }
            if permissions.allGranted {
                Section {
                    Label("You’re all set. Open Sill on your iPhone or iPad.", systemImage: "checkmark.seal.fill")
                }
            }
        }
    }

    private static func networkNeedsHelp(_ network: HostStatusSnapshot.Network?) -> Bool {
        switch network {
        case .waiting, .failed: return true
        default: return false
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let allowed: Bool
    let explanation: String
    let button: String
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button(button, action: action)
                }
            }
        } label: {
            Text(title)
            Text(explanation)
        }
    }
}
