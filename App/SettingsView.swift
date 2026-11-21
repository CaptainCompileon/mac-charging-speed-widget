import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var monitor: PowerMonitor
    @Bindable var updater: UpdateManager
    let onOpenUpdatePrompt: () -> Void

    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var loginStatusError: String?

    var body: some View {
        Form {
            Section("Menu Bar Display") {
                Picker("Status Item Format", selection: $monitor.menuBarMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Polling Interval", selection: $monitor.pollingInterval) {
                    Text("1 second (Live)").tag(1.0)
                    Text("2 seconds (Balanced)").tag(2.0)
                    Text("5 seconds (Ultra Low Power)").tag(5.0)
                }

                Toggle("Show Temperature in Fahrenheit (°F)", isOn: $monitor.useFahrenheit)
            }

            Section("Software Updates") {
                Toggle("Automatic Background Updates", isOn: $updater.automaticUpdatesEnabled)

                Picker("Check Frequency", selection: $updater.checkIntervalHours) {
                    Text("Every 2 hours").tag(2)
                    Text("Every 6 hours").tag(6)
                    Text("Once a day").tag(24)
                }
                .disabled(!updater.automaticUpdatesEnabled)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(updateStatusLine)
                            .font(.system(size: 12))
                        Text(updateSecondaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updater.hasUpdateAvailable ? "Update Now…" : "Check Now…") {
                        onOpenUpdatePrompt()
                    }
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }

                if let loginStatusError {
                    Text(loginStatusError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Widgets & History") {
                HStack {
                    Button("Sync Desktop Widgets Now") {
                        monitor.refreshNow(forceWidgetReload: true)
                    }
                    Spacer()
                    Button("Clear Curve History", role: .destructive) {
                        monitor.clearHistory()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 470)
    }

    private var updateStatusLine: String {
        if let release = updater.availableRelease {
            return "Version \(release.version) is available (installed: \(updater.currentVersion))"
        }
        return "Installed version \(updater.currentVersion) (build \(updater.currentBuild))"
    }

    private var updateSecondaryLine: String {
        if let checked = updater.lastCheckedDate {
            return "Last checked \(checked.formatted(date: .abbreviated, time: .shortened)) · Prompts on cold start"
        }
        return "Prompts on cold start with update status"
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginStatusError = nil
        } catch {
            loginStatusError = "Move MacChargingSpeed.app to /Applications to enable Launch at Login."
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
