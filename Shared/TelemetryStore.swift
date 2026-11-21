import Foundation

/// Persists rolling power-curve samples and shared settings between the Menu Bar App and WidgetKit.
public final class TelemetryStore: @unchecked Sendable {
    public static let shared = TelemetryStore()

    public static let appGroupIdentifier = "group.com.captaincompileon.MacChargingSpeed"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let historyKey = "macchargingspeed.history.v1"
    private let latestKey = "macchargingspeed.latest.v1"
    private let maxHistoryCount = 90

    public init(defaults: UserDefaults? = nil) {
        if let provided = defaults {
            self.defaults = provided
        } else if let groupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            self.defaults = groupDefaults
        } else {
            self.defaults = .standard
        }
    }

    public func saveSnapshot(_ telemetry: PowerTelemetry, appendToHistory: Bool = true) {
        lock.lock()
        defer { lock.unlock() }

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(telemetry) {
            defaults.set(data, forKey: latestKey)
        }

        guard appendToHistory else { return }

        var history = loadHistoryLocked()
        let newPoint = PowerHistoryPoint(
            timestamp: telemetry.timestamp,
            totalWatts: telemetry.headlineWatts,
            batteryWatts: telemetry.batteryNetWatts,
            systemLoadWatts: telemetry.systemLoadWatts,
            batteryPercent: telemetry.batteryPercent
        )

        // Avoid storing duplicate samples closer than 5 seconds apart so the sparkline spans ~7.5 minutes+.
        if let last = history.last, newPoint.timestamp.timeIntervalSince(last.timestamp) < 5.0 {
            history[history.count - 1] = newPoint
        } else {
            history.append(newPoint)
        }

        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        if let encodedHistory = try? encoder.encode(history) {
            defaults.set(encodedHistory, forKey: historyKey)
        }
    }

    public func loadLatestSnapshot() -> PowerTelemetry? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: latestKey) else { return nil }
        return try? JSONDecoder().decode(PowerTelemetry.self, from: data)
    }

    public func loadHistory() -> [PowerHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return loadHistoryLocked()
    }

    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: historyKey)
    }

    // MARK: - Shared User Preferences

    public var useFahrenheit: Bool {
        get { defaults.bool(forKey: "pref.useFahrenheit") }
        set { defaults.set(newValue, forKey: "pref.useFahrenheit") }
    }

    public var menuBarMode: MenuBarDisplayMode {
        get {
            guard let raw = defaults.string(forKey: "pref.menuBarMode"),
                  let mode = MenuBarDisplayMode(rawValue: raw) else {
                return .wattsOnly
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "pref.menuBarMode") }
    }

    public var pollingIntervalSeconds: Double {
        get {
            let value = defaults.double(forKey: "pref.pollingInterval")
            return value >= 1.0 ? value : 1.0
        }
        set { defaults.set(max(1.0, newValue), forKey: "pref.pollingInterval") }
    }

    private func loadHistoryLocked() -> [PowerHistoryPoint] {
        guard let data = defaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([PowerHistoryPoint].self, from: data) else {
            return []
        }
        return decoded
    }
}
