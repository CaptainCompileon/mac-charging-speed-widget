import Foundation
import IOKit
import IOKit.ps

/// Direct, zero-subprocess reader for macOS `AppleSmartBattery`, `PowerTelemetryData`,
/// `AdapterDetails`, and `IOPSCopyPowerSourcesInfo`.
/// Works on both Apple Silicon (M1–M5) and Intel Macs with negligible CPU overhead.
public enum IOKitPowerReader {
    public static func readCurrentTelemetry() -> PowerTelemetry {
        let registryProps = readAppleSmartBatteryProperties()
        let psInfo = readIOPSPowerSourceFallback()

        let isExternalConnected = boolValue(registryProps, key: "ExternalConnected")
            ?? psInfo.isExternalConnected
            ?? false
        let isCharging = boolValue(registryProps, key: "IsCharging")
            ?? psInfo.isCharging
            ?? false
        let isFullyCharged = boolValue(registryProps, key: "FullyCharged")
            ?? psInfo.isFullyCharged
            ?? false

        // MARK: - Capacity & Battery Health
        let designCapacity = intValue(registryProps, key: "DesignCapacity") ?? 5000
        let rawMaxCapacity = intValue(registryProps, key: "AppleRawMaxCapacity")
            ?? intValue(registryProps, key: "NominalChargeCapacity")
            ?? intValue(registryProps, key: "MaxCapacity")
            ?? designCapacity
        let rawCurrentCapacity = intValue(registryProps, key: "AppleRawCurrentCapacity")
            ?? intValue(registryProps, key: "CurrentCapacity")
            ?? 0

        // Apple Silicon normalizes `CurrentCapacity` / `MaxCapacity` to 0..100.
        let batteryPercent: Int = {
            if let pct = psInfo.percent { return min(max(pct, 0), 100) }
            if let maxCap = intValue(registryProps, key: "MaxCapacity"),
               let curCap = intValue(registryProps, key: "CurrentCapacity"),
               maxCap > 0 {
                return min(max(Int((Double(curCap) / Double(maxCap) * 100.0).rounded()), 0), 100)
            }
            if rawMaxCapacity > 0 {
                return min(max(Int((Double(rawCurrentCapacity) / Double(rawMaxCapacity) * 100.0).rounded()), 0), 100)
            }
            return 0
        }()

        let healthPercent: Double = {
            guard designCapacity > 0 else { return 100.0 }
            let ratio = (Double(rawMaxCapacity) / Double(designCapacity)) * 100.0
            return min(max(ratio, 0.0), 105.0)
        }()

        let cycleCount = intValue(registryProps, key: "CycleCount") ?? 0
        let designCycleCount = intValue(registryProps, key: "DesignCycleCount9C")
            ?? intValue(registryProps, key: "DesignCycleCount")
            ?? 1000

        // MARK: - Pack Voltage & Signed Current (mV / mA)
        let voltageMv = intValue(registryProps, key: "Voltage") ?? 0
        let voltageV = Double(voltageMv) / 1000.0

        // IOKit often stores negative InstantAmperage as unsigned 64-bit two's complement.
        let instantAmperageMa = signedInt64Value(registryProps, key: "InstantAmperage")
            ?? signedInt64Value(registryProps, key: "Amperage")
            ?? 0
        let amperageA = Double(instantAmperageMa) / 1000.0
        let batteryNetWatts = voltageV * amperageA

        // MARK: - PowerTelemetryData (Apple Silicon Power Flow Split)
        let telemetryDict = registryProps["PowerTelemetryData"] as? [String: Any]
        let systemPowerInMw = intValue(telemetryDict, key: "SystemPowerIn")
        let systemLoadMw = intValue(telemetryDict, key: "SystemLoad")
        let systemVoltageInMv = intValue(telemetryDict, key: "SystemVoltageIn")
            ?? intValue(telemetryDict, key: "SystemInputVoltage")
        let systemCurrentInMa = intValue(telemetryDict, key: "SystemCurrentIn")
            ?? intValue(telemetryDict, key: "SystemInputCurrent")

        let adapterVoltageV: Double? = systemVoltageInMv.flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }
        let adapterCurrentA: Double? = systemCurrentInMa.flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }

        let adapterInputWatts: Double = {
            guard isExternalConnected else { return 0.0 }
            if let powerInMw = systemPowerInMw, powerInMw > 0 {
                return Double(powerInMw) / 1000.0
            }
            if let v = adapterVoltageV, let a = adapterCurrentA {
                return v * a
            }
            // Fallback for Intel Macs where PowerTelemetryData is absent
            if let loadMw = systemLoadMw, loadMw > 0 {
                return max(Double(loadMw) / 1000.0 + max(batteryNetWatts, 0), 0)
            }
            return max(batteryNetWatts, 0)
        }()

        let systemLoadWatts: Double = {
            if let loadMw = systemLoadMw, loadMw > 0 {
                return Double(loadMw) / 1000.0
            }
            if isExternalConnected {
                return max(adapterInputWatts - max(batteryNetWatts, 0), 0)
            }
            return abs(batteryNetWatts)
        }()

        // MARK: - Battery Temperature & Cell Voltages
        let temperatureC = parseTemperatureCelsius(registryProps)
        let cellVoltagesMv: [Int] = {
            if let batteryData = registryProps["BatteryData"] as? [String: Any],
               let cells = batteryData["CellVoltage"] as? [NSNumber] {
                return cells.map(\.intValue).filter { $0 > 0 }
            }
            return []
        }()

        // MARK: - Time Remaining
        let timeRemainingMinutes: Int? = {
            if isCharging {
                let raw = intValue(registryProps, key: "AvgTimeToFull")
                    ?? intValue(registryProps, key: "InstantTimeToFull")
                    ?? psInfo.timeToFull
                if let val = raw, val > 0, val < 65535 { return val }
            } else if !isExternalConnected {
                let raw = intValue(registryProps, key: "AvgTimeToEmpty")
                    ?? intValue(registryProps, key: "TimeRemaining")
                    ?? psInfo.timeToEmpty
                if let val = raw, val > 0, val < 65535 { return val }
            }
            return nil
        }()

        // MARK: - Adapter Hardware Details
        let adapterInfo = parseAdapterInfo(
            registryProps: registryProps,
            isExternalConnected: isExternalConnected,
            fallbackWatts: psInfo.adapterWatts
        )

        // MARK: - Charging Phase Classification
        let phase = classifyPhase(
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            batteryPercent: batteryPercent,
            batteryNetWatts: batteryNetWatts,
            adapterInputWatts: adapterInputWatts
        )

        return PowerTelemetry(
            timestamp: Date(),
            adapterInputWatts: adapterInputWatts,
            batteryNetWatts: batteryNetWatts,
            systemLoadWatts: systemLoadWatts,
            voltageV: voltageV,
            amperageA: amperageA,
            adapterVoltageV: adapterVoltageV ?? adapterInfo?.negotiatedVoltageV,
            adapterCurrentA: adapterCurrentA ?? adapterInfo?.negotiatedCurrentA,
            batteryPercent: batteryPercent,
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            phase: phase,
            timeRemainingMinutes: timeRemainingMinutes,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            designCapacityMah: designCapacity,
            maxCapacityMah: rawMaxCapacity,
            currentCapacityMah: rawCurrentCapacity,
            batteryHealthPercent: healthPercent,
            temperatureC: temperatureC,
            cellVoltagesMv: cellVoltagesMv,
            thermalLevel: SystemThermalLevel.current(),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            adapter: adapterInfo
        )
    }

    // MARK: - Private IOKit Helpers

    private static func readAppleSmartBatteryProperties() -> [String: Any] {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return [:] }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(service) }

        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let props = unmanagedProps?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return props
    }

    private struct IOPSFallback {
        var percent: Int?
        var isExternalConnected: Bool?
        var isCharging: Bool?
        var isFullyCharged: Bool?
        var timeToFull: Int?
        var timeToEmpty: Int?
        var adapterWatts: Int?
    }

    private static func readIOPSPowerSourceFallback() -> IOPSFallback {
        var result = IOPSFallback()

        if let adapterCF = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapterCF[kIOPSPowerAdapterWattsKey] as? Int {
            result.adapterWatts = watts
        }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return result
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
               let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                result.percent = Int((Double(cur) / Double(maxCap) * 100.0).rounded())
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                result.isExternalConnected = (state == kIOPSACPowerValue)
            }
            result.isCharging = desc[kIOPSIsChargingKey] as? Bool
            result.isFullyCharged = desc[kIOPSIsChargedKey] as? Bool
            if let ttf = desc[kIOPSTimeToFullChargeKey] as? Int, ttf > 0 {
                result.timeToFull = ttf
            }
            if let tte = desc[kIOPSTimeToEmptyKey] as? Int, tte > 0 {
                result.timeToEmpty = tte
            }
            break
        }
        return result
    }

    private static func parseTemperatureCelsius(_ props: [String: Any]) -> Double? {
        let raw = intValue(props, key: "Temperature") ?? intValue(props, key: "VirtualTemperature")
        guard let raw, raw > 0 else { return nil }

        // Handle centi-Kelvin (> 20000), centi-Celsius (1000...10000), or deci-Kelvin fallback.
        if raw > 20_000 {
            return (Double(raw) / 100.0) - 273.15
        }
        let centiC = Double(raw) / 100.0
        if (5.0...95.0).contains(centiC) {
            return centiC
        }
        return nil
    }

    private static func parseAdapterInfo(
        registryProps: [String: Any],
        isExternalConnected: Bool,
        fallbackWatts: Int?
    ) -> AdapterHardwareInfo? {
        guard isExternalConnected else { return nil }

        let details = registryProps["AdapterDetails"] as? [String: Any]
            ?? (registryProps["AppleRawAdapterDetails"] as? [[String: Any]])?.first

        let watts = intValue(details, key: "Watts") ?? fallbackWatts ?? 0
        let voltageMv = intValue(details, key: "AdapterVoltage")
        let currentMa = intValue(details, key: "Current")
        let negotiatedV = voltageMv.flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }
        let negotiatedA = currentMa.flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }

        let rawName = (details?["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let manufacturer = (details?["Manufacturer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let serial = (details?["SerialString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDesc = (details?["Description"] as? String)?.lowercased() ?? ""

        let displayName: String = {
            if let rawName, !rawName.isEmpty { return rawName }
            if watts > 0 { return "\(watts)W USB-C Power Adapter" }
            return "External Power Adapter"
        }()

        let isMagSafe = rawDesc.contains("magsafe") || displayName.lowercased().contains("magsafe")
        let protocolDesc: String = {
            if watts >= 100 { return "USB-PD EPR" }
            if rawDesc.contains("pd") || (negotiatedV ?? 0) >= 9.0 { return "USB-PD" }
            if isMagSafe { return "MagSafe" }
            return "USB-C Power"
        }()

        return AdapterHardwareInfo(
            name: displayName,
            manufacturer: manufacturer?.isEmpty == false ? manufacturer : nil,
            maxWatts: watts,
            negotiatedVoltageV: negotiatedV,
            negotiatedCurrentA: negotiatedA,
            protocolDescription: protocolDesc,
            serialNumber: serial?.isEmpty == false ? serial : nil,
            isWirelessOrMagSafe: isMagSafe
        )
    }

    private static func classifyPhase(
        isExternalConnected: Bool,
        isCharging: Bool,
        isFullyCharged: Bool,
        batteryPercent: Int,
        batteryNetWatts: Double,
        adapterInputWatts: Double
    ) -> ChargingPhase {
        if !isExternalConnected {
            return .discharging
        }
        if isFullyCharged || batteryPercent >= 100 {
            return .full
        }
        if isCharging {
            if batteryNetWatts >= 45.0 || adapterInputWatts >= 60.0 {
                return .fastCharging
            }
            if batteryNetWatts < 10.0 && batteryPercent >= 80 {
                return .trickleCharging
            }
            return .charging
        }
        if batteryPercent >= 78 && batteryPercent <= 82 {
            return .optimizedHold
        }
        return .acPassthrough
    }

    private static func intValue(_ dict: [String: Any]?, key: String) -> Int? {
        guard let value = dict?[key] else { return nil }
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        return nil
    }

    private static func signedInt64Value(_ dict: [String: Any]?, key: String) -> Int64? {
        guard let value = dict?[key] else { return nil }
        if let n = value as? NSNumber {
            return Int64(bitPattern: n.uint64Value)
        }
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        return nil
    }

    private static func boolValue(_ dict: [String: Any]?, key: String) -> Bool? {
        guard let value = dict?[key] else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
}
