import Foundation

/// High-level charging phase inferred from battery state, wattage, and USB-PD negotiation.
public enum ChargingPhase: String, Codable, Sendable, CaseIterable {
    case fastCharging = "Fast Charging"
    case charging = "Charging"
    case trickleCharging = "Trickle Charge"
    case optimizedHold = "Optimized Hold"
    case acPassthrough = "AC Passthrough"
    case discharging = "On Battery"
    case full = "Fully Charged"

    public var shortLabel: String {
        switch self {
        case .fastCharging: return "Fast Charge"
        case .charging: return "Charging"
        case .trickleCharging: return "Trickle"
        case .optimizedHold: return "Optimized"
        case .acPassthrough: return "AC Power"
        case .discharging: return "Battery"
        case .full: return "Charged"
        }
    }

    public var symbolName: String {
        switch self {
        case .fastCharging: return "bolt.fill"
        case .charging: return "bolt.badge.checkmark.fill"
        case .trickleCharging: return "bolt.horizontal.fill"
        case .optimizedHold: return "leaf.fill"
        case .acPassthrough: return "powerplug.fill"
        case .discharging: return "battery.75percent"
        case .full: return "checkmark.circle.fill"
        }
    }
}

/// Thermal pressure level mapped from `ProcessInfo.ThermalState`.
public enum SystemThermalLevel: String, Codable, Sendable {
    case nominal = "Nominal"
    case fair = "Warm"
    case serious = "Elevated"
    case critical = "Throttled"

    public static func current() -> SystemThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}

/// Hardware details reported by the USB-PD / MagSafe power adapter.
public struct AdapterHardwareInfo: Codable, Sendable, Equatable {
    public let name: String
    public let manufacturer: String?
    public let maxWatts: Int
    public let negotiatedVoltageV: Double?
    public let negotiatedCurrentA: Double?
    public let protocolDescription: String
    public let serialNumber: String?
    public let isWirelessOrMagSafe: Bool

    public init(
        name: String,
        manufacturer: String? = nil,
        maxWatts: Int,
        negotiatedVoltageV: Double? = nil,
        negotiatedCurrentA: Double? = nil,
        protocolDescription: String,
        serialNumber: String? = nil,
        isWirelessOrMagSafe: Bool = false
    ) {
        self.name = name
        self.manufacturer = manufacturer
        self.maxWatts = maxWatts
        self.negotiatedVoltageV = negotiatedVoltageV
        self.negotiatedCurrentA = negotiatedCurrentA
        self.protocolDescription = protocolDescription
        self.serialNumber = serialNumber
        self.isWirelessOrMagSafe = isWirelessOrMagSafe
    }
}

/// Single timestamped power sample for the real-time charging curve sparkline.
public struct PowerHistoryPoint: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    /// Positive = charging into battery / wall input; Negative = net battery discharge.
    public let totalWatts: Double
    public let batteryWatts: Double
    public let systemLoadWatts: Double
    public let batteryPercent: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        totalWatts: Double,
        batteryWatts: Double,
        systemLoadWatts: Double,
        batteryPercent: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.totalWatts = totalWatts
        self.batteryWatts = batteryWatts
        self.systemLoadWatts = systemLoadWatts
        self.batteryPercent = batteryPercent
    }
}

/// Complete real-time snapshot of Mac power, charging, and battery health telemetry.
public struct PowerTelemetry: Codable, Sendable, Equatable {
    public let timestamp: Date

    // MARK: - Core Power Metrics
    /// Total live power entering from the wall adapter (W). Zero when on battery.
    public let adapterInputWatts: Double
    /// Net power flowing into (+) or out of (-) the battery pack (W).
    public let batteryNetWatts: Double
    /// Live power consumed by the MacBook system (SoC, display, peripherals) (W).
    public let systemLoadWatts: Double

    /// Pack or input voltage in Volts (V).
    public let voltageV: Double
    /// Instantaneous battery current in Amperes (A). Positive = charging, negative = discharging.
    public let amperageA: Double
    /// Adapter input voltage in Volts (V) when reported by `PowerTelemetryData`.
    public let adapterVoltageV: Double?
    /// Adapter input current in Amperes (A) when reported by `PowerTelemetryData`.
    public let adapterCurrentA: Double?

    // MARK: - Battery State & Capacity
    public let batteryPercent: Int
    public let isExternalConnected: Bool
    public let isCharging: Bool
    public let isFullyCharged: Bool
    public let phase: ChargingPhase
    /// Minutes until full (when charging) or empty (when discharging). `nil` if calculating / idle.
    public let timeRemainingMinutes: Int?

    // MARK: - Health & Thermals
    public let cycleCount: Int
    public let designCycleCount: Int
    public let designCapacityMah: Int
    public let maxCapacityMah: Int
    public let currentCapacityMah: Int
    /// Maximum capacity percentage (`maxCapacityMah / designCapacityMah * 100`).
    public let batteryHealthPercent: Double
    /// Battery pack temperature in Celsius (`nil` if sensor unavailable).
    public let temperatureC: Double?
    /// Individual battery cell voltages in millivolts, if exposed by `BatteryData.CellVoltage`.
    public let cellVoltagesMv: [Int]
    public let thermalLevel: SystemThermalLevel
    public let isLowPowerMode: Bool

    // MARK: - Adapter Metadata
    public let adapter: AdapterHardwareInfo?

    public init(
        timestamp: Date = Date(),
        adapterInputWatts: Double,
        batteryNetWatts: Double,
        systemLoadWatts: Double,
        voltageV: Double,
        amperageA: Double,
        adapterVoltageV: Double? = nil,
        adapterCurrentA: Double? = nil,
        batteryPercent: Int,
        isExternalConnected: Bool,
        isCharging: Bool,
        isFullyCharged: Bool,
        phase: ChargingPhase,
        timeRemainingMinutes: Int?,
        cycleCount: Int,
        designCycleCount: Int = 1000,
        designCapacityMah: Int,
        maxCapacityMah: Int,
        currentCapacityMah: Int,
        batteryHealthPercent: Double,
        temperatureC: Double?,
        cellVoltagesMv: [Int] = [],
        thermalLevel: SystemThermalLevel = .nominal,
        isLowPowerMode: Bool = false,
        adapter: AdapterHardwareInfo? = nil
    ) {
        self.timestamp = timestamp
        self.adapterInputWatts = adapterInputWatts
        self.batteryNetWatts = batteryNetWatts
        self.systemLoadWatts = systemLoadWatts
        self.voltageV = voltageV
        self.amperageA = amperageA
        self.adapterVoltageV = adapterVoltageV
        self.adapterCurrentA = adapterCurrentA
        self.batteryPercent = batteryPercent
        self.isExternalConnected = isExternalConnected
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.phase = phase
        self.timeRemainingMinutes = timeRemainingMinutes
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.designCapacityMah = designCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.batteryHealthPercent = batteryHealthPercent
        self.temperatureC = temperatureC
        self.cellVoltagesMv = cellVoltagesMv
        self.thermalLevel = thermalLevel
        self.isLowPowerMode = isLowPowerMode
        self.adapter = adapter
    }

    // MARK: - Computed Display Helpers

    /// Headline wattage shown prominently in widgets and the menu bar.
    /// Shows total wall input when plugged in, or system discharge draw when on battery.
    public var headlineWatts: Double {
        if isExternalConnected {
            return max(adapterInputWatts, max(batteryNetWatts, 0) + systemLoadWatts)
        } else {
            return abs(batteryNetWatts) > 0.1 ? abs(batteryNetWatts) : systemLoadWatts
        }
    }

    /// Headline voltage: prefers USB-PD input voltage when plugged in, otherwise battery pack voltage.
    public var displayVoltageV: Double {
        if isExternalConnected, let adapterV = adapterVoltageV, adapterV > 1.0 {
            return adapterV
        }
        return voltageV
    }

    /// Headline current: prefers USB-PD input current when plugged in, otherwise battery pack current.
    public var displayCurrentA: Double {
        if isExternalConnected, let adapterA = adapterCurrentA, adapterA > 0.05 {
            return adapterA
        }
        return abs(amperageA)
    }

    /// Cell voltage imbalance in mV (max - min) for power-user diagnostics.
    public var cellDeltaMv: Int? {
        guard let minV = cellVoltagesMv.min(), let maxV = cellVoltagesMv.max(), cellVoltagesMv.count > 1 else {
            return nil
        }
        return maxV - minV
    }

    /// Fraction of negotiated charger wattage currently utilized (0.0...1.0).
    public var adapterUtilization: Double? {
        guard isExternalConnected, let maxW = adapter?.maxWatts, maxW > 0 else { return nil }
        return min(max(headlineWatts / Double(maxW), 0), 1)
    }

    public func formattedWatts(_ value: Double, signed: Bool = false) -> String {
        if signed {
            let prefix = value >= 0.05 ? "+" : (value <= -0.05 ? "−" : "")
            return String(format: "%@%.1f W", prefix, abs(value))
        }
        return String(format: "%.1f W", value)
    }

    public var formattedETA: String? {
        guard let mins = timeRemainingMinutes, mins > 0, mins < 6000 else { return nil }
        let hours = mins / 60
        let rem = mins % 60
        if hours > 0 {
            return "\(hours)h \(rem)m"
        }
        return "\(rem)m"
    }

    public var etaDescription: String {
        if let eta = formattedETA {
            return isCharging ? "\(eta) to full" : "\(eta) left"
        }
        switch phase {
        case .full: return "100% charged"
        case .optimizedHold: return "Holding at \(batteryPercent)%"
        case .acPassthrough: return "Running on AC"
        default: return "Calculating…"
        }
    }

    public func formattedTemperature(useFahrenheit: Bool) -> String {
        guard let c = temperatureC else { return "—" }
        if useFahrenheit {
            let f = (c * 9.0 / 5.0) + 32.0
            return String(format: "%.1f°F", f)
        }
        return String(format: "%.1f°C", c)
    }

    // MARK: - Rich Preview / Placeholder Data

    public static let previewFastCharge = PowerTelemetry(
        timestamp: Date(),
        adapterInputWatts: 94.2,
        batteryNetWatts: 69.4,
        systemLoadWatts: 24.8,
        voltageV: 12.68,
        amperageA: 5.47,
        adapterVoltageV: 20.0,
        adapterCurrentA: 4.71,
        batteryPercent: 78,
        isExternalConnected: true,
        isCharging: true,
        isFullyCharged: false,
        phase: .fastCharging,
        timeRemainingMinutes: 28,
        cycleCount: 42,
        designCycleCount: 1000,
        designCapacityMah: 6075,
        maxCapacityMah: 5954,
        currentCapacityMah: 4644,
        batteryHealthPercent: 98.0,
        temperatureC: 31.4,
        cellVoltagesMv: [4226, 4228, 4225],
        thermalLevel: .nominal,
        isLowPowerMode: false,
        adapter: AdapterHardwareInfo(
            name: "140W USB-C Power Adapter",
            manufacturer: "Apple Inc.",
            maxWatts: 140,
            negotiatedVoltageV: 20.0,
            negotiatedCurrentA: 5.0,
            protocolDescription: "USB-PD EPR",
            serialNumber: "C4H219400G1K9M",
            isWirelessOrMagSafe: true
        )
    )

    public static let previewDischarging = PowerTelemetry(
        timestamp: Date(),
        adapterInputWatts: 0.0,
        batteryNetWatts: -14.6,
        systemLoadWatts: 14.6,
        voltageV: 11.84,
        amperageA: -1.23,
        adapterVoltageV: nil,
        adapterCurrentA: nil,
        batteryPercent: 64,
        isExternalConnected: false,
        isCharging: false,
        isFullyCharged: false,
        phase: .discharging,
        timeRemainingMinutes: 312,
        cycleCount: 42,
        designCycleCount: 1000,
        designCapacityMah: 6075,
        maxCapacityMah: 5954,
        currentCapacityMah: 3810,
        batteryHealthPercent: 98.0,
        temperatureC: 29.1,
        cellVoltagesMv: [3946, 3948, 3946],
        thermalLevel: .nominal,
        isLowPowerMode: false,
        adapter: nil
    )

    public static var previewHistory: [PowerHistoryPoint] {
        let now = Date()
        let wattsSeries: [Double] = [
            42.0, 58.5, 72.1, 86.4, 94.8, 96.2, 95.4, 91.2,
            93.6, 95.8, 94.1, 92.8, 94.6, 95.0, 93.9, 94.2
        ]
        return wattsSeries.enumerated().map { idx, watts in
            let sys = 22.0 + Double(idx % 4) * 1.1
            return PowerHistoryPoint(
                timestamp: now.addingTimeInterval(Double(idx - wattsSeries.count) * 120),
                totalWatts: watts,
                batteryWatts: max(watts - sys, 0),
                systemLoadWatts: sys,
                batteryPercent: min(78, 54 + idx * 2)
            )
        }
    }
}

/// Display options for the live menu bar status item.
public enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case wattsOnly = "Watts"
    case wattsAndPercent = "Watts + %"
    case wattsAndAmps = "Watts + Amps"
    case compactIcon = "Icon Only"

    public var id: String { rawValue }
}
