import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var monitor: PowerMonitor
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
        .frame(width: 420, height: 310)
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
