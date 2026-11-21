import AppKit
import SwiftUI

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    let updater = UpdateManager()
    let updateWindow = UpdateWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Brief settle so MenuBarExtra finishes registering before presenting the cold-start update prompt.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            self.updateWindow.present(updater: self.updater, isColdStart: true)
            await self.updater.checkOnColdStart()
        }
    }

    func presentManualUpdateCheck() {
        updateWindow.present(updater: updater, isColdStart: false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updater.checkForUpdates(isBackground: false)
        }
    }
}

@main
struct MacChargingSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @State private var monitor = PowerMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(
                monitor: monitor,
                updater: appDelegate.updater,
                onCheckUpdates: {
                    appDelegate.presentManualUpdateCheck()
                }
            )
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
            SettingsView(
                monitor: monitor,
                updater: appDelegate.updater,
                onOpenUpdatePrompt: {
                    appDelegate.presentManualUpdateCheck()
                }
            )
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(
                monitor: monitor,
                updater: appDelegate.updater,
                onOpenUpdatePrompt: {
                    appDelegate.presentManualUpdateCheck()
                }
            )
        }
    }
}
