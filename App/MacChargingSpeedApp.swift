import SwiftUI

@main
struct MacChargingSpeedApp: App {
    @State private var monitor = PowerMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: monitor.menuBarSymbol)
                    .symbolRenderingMode(.hierarchical)
                if !monitor.menuBarLabel.isEmpty {
                    Text(monitor.menuBarLabel)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("MacChargingSpeed Settings", id: "settings") {
            SettingsView(monitor: monitor)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(monitor: monitor)
        }
    }
}
