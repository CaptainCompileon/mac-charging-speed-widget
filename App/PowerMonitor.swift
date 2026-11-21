import Foundation
import Observation
import WidgetKit

/// Live 1-second telemetry monitor driving the Menu Bar status item, Popover, and WidgetKit sync.
@MainActor
@Observable
public final class PowerMonitor {
    public private(set) var telemetry: PowerTelemetry
    public private(set) var history: [PowerHistoryPoint]
    public var useFahrenheit: Bool {
        didSet { TelemetryStore.shared.useFahrenheit = useFahrenheit }
    }
    public var menuBarMode: MenuBarDisplayMode {
        didSet { TelemetryStore.shared.menuBarMode = menuBarMode }
    }
    public var pollingInterval: Double {
        didSet {
            TelemetryStore.shared.pollingIntervalSeconds = pollingInterval
            restartTimer()
        }
    }

    private var pollingTask: Task<Void, Never>?
    private var lastWidgetReload: Date = .distantPast
    private var lastExternalState: Bool?
    private var lastChargingState: Bool?

    public init() {
        let store = TelemetryStore.shared
        self.useFahrenheit = store.useFahrenheit
        self.menuBarMode = store.menuBarMode
        self.pollingInterval = store.pollingIntervalSeconds

        let initial = IOKitPowerReader.readCurrentTelemetry()
        self.telemetry = initial
        store.saveSnapshot(initial, appendToHistory: true)
        self.history = store.loadHistory()
        self.lastExternalState = initial.isExternalConnected
        self.lastChargingState = initial.isCharging

        startMonitoring()
    }

    public func startMonitoring() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(1.0, self.pollingInterval)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self.refreshNow(forceWidgetReload: false)
            }
        }
    }

    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func refreshNow(forceWidgetReload: Bool = false) {
        let snapshot = IOKitPowerReader.readCurrentTelemetry()
        self.telemetry = snapshot

        let store = TelemetryStore.shared
        store.saveSnapshot(snapshot, appendToHistory: true)
        self.history = store.loadHistory()

        let powerStateChanged = (lastExternalState != snapshot.isExternalConnected)
            || (lastChargingState != snapshot.isCharging)
        lastExternalState = snapshot.isExternalConnected
        lastChargingState = snapshot.isCharging

        let elapsed = Date().timeIntervalSince(lastWidgetReload)
        if forceWidgetReload || powerStateChanged || elapsed >= 60.0 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: "MacChargingSpeedWidget")
        }
    }

    public func clearHistory() {
        TelemetryStore.shared.clearHistory()
        TelemetryStore.shared.saveSnapshot(telemetry, appendToHistory: true)
        history = TelemetryStore.shared.loadHistory()
        WidgetCenter.shared.reloadTimelines(ofKind: "MacChargingSpeedWidget")
    }

    public var menuBarLabel: String {
        switch menuBarMode {
        case .wattsOnly:
            return String(format: "%.1fW", telemetry.headlineWatts)
        case .wattsAndPercent:
            return String(format: "%.0fW · %d%%", telemetry.headlineWatts, telemetry.batteryPercent)
        case .wattsAndAmps:
            return String(format: "%.1fW · %.1fA", telemetry.headlineWatts, telemetry.displayCurrentA)
        case .compactIcon:
            return ""
        }
    }

    public var menuBarSymbol: String {
        if telemetry.isCharging {
            return "bolt.fill"
        } else if telemetry.isExternalConnected {
            return "powerplug.fill"
        } else if telemetry.batteryPercent <= 15 {
            return "battery.25percent"
        } else {
            return "battery.75percent"
        }
    }

    private func restartTimer() {
        stopMonitoring()
        startMonitoring()
    }
}
