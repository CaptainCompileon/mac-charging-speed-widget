import Foundation
import IOKit
import IOKit.ps

/// Direct, zero-subprocess reader for macOS `AppleSmartBattery`, `AppleSmartBatteryPack`,
/// `PowerTelemetryData`, `AdapterDetails`, and `IOPSCopyPowerSourcesInfo`.
/// Works across Intel and Apple Silicon (M1–M5) on macOS 14 through macOS 27+.
public enum IOKitPowerReader {
    /// Fallback fields from `IOPSCopyPowerSourcesInfo` and `IOPSCopyExternalPowerAdapterDetails`.
    public struct IOPSFallback: Sendable {
        public var percent: Int?
        public var isExternalConnected: Bool?
        public var isCharging: Bool?
        public var isFullyCharged: Bool?
        public var timeToFull: Int?
        public var timeToEmpty: Int?
        public var adapterWatts: Int?

        public init(
            percent: Int? = nil,
            isExternalConnected: Bool? = nil,
            isCharging: Bool? = nil,
            isFullyCharged: Bool? = nil,
            timeToFull: Int? = nil,
            timeToEmpty: Int? = nil,
            adapterWatts: Int? = nil
        ) {
            self.percent = percent
            self.isExternalConnected = isExternalConnected
            self.isCharging = isCharging
            self.isFullyCharged = isFullyCharged
            self.timeToFull = timeToFull
            self.timeToEmpty = timeToEmpty
            self.adapterWatts = adapterWatts
        }
    }

    public static func readCurrentTelemetry() -> PowerTelemetry {
        let (registryProps, batteryPackProps) = readBatteryRegistryDictionaries()
        let psInfo = readIOPSPowerSourceFallback()
        return parse(
            registryProps: registryProps,
            batteryPackProps: batteryPackProps,
            iopsFallback: psInfo,
            thermalLevel: SystemThermalLevel.current(),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            now: Date()
        )
    }

    /// Pure, deterministic parser for IOKit battery & power dictionaries.
    /// Exposed publicly so unit tests can validate real Intel, Apple Silicon, and macOS 26/27 snapshots.
    public static func parse(
        registryProps: [String: Any],
        batteryPackProps: [String: Any] = [:],
        iopsFallback: IOPSFallback = IOPSFallback(),
        thermalLevel: SystemThermalLevel = .nominal,
        isLowPowerMode: Bool = false,
        now: Date = Date()
    ) -> PowerTelemetry {
        let batteryData = registryProps["BatteryData"] as? [String: Any] ?? [:]
        let packBatteryData = batteryPackProps["BatteryData"] as? [String: Any] ?? [:]

        // Ordered lookup scopes: top-level AppleSmartBattery -> nested BatteryData -> child AppleSmartBatteryPack -> its BatteryData
        let allScopes: [[String: Any]] = [registryProps, batteryData, batteryPackProps, packBatteryData]

        let isExternalConnected = boolValue(registryProps, key: "ExternalConnected")
            ?? iopsFallback.isExternalConnected
            ?? false
        let isChargingFlag = boolValue(registryProps, key: "IsCharging")
            ?? iopsFallback.isCharging
            ?? false
        let isFullyCharged = boolValue(registryProps, key: "FullyCharged")
            ?? iopsFallback.isFullyCharged
            ?? false

        // MARK: - Charge Percentage
        let topMaxCap = positiveInt(in: [registryProps], keys: ["MaxCapacity"])
        let topCurCap = nonNegativeInt(in: [registryProps], keys: ["CurrentCapacity"])

        let batteryPercent: Int = {
            if let pct = iopsFallback.percent { return min(max(pct, 0), 100) }
            if let maxCap = topMaxCap, let curCap = topCurCap, maxCap > 0 {
                return min(max(Int((Double(curCap) / Double(maxCap) * 100.0).rounded()), 0), 100)
            }
            if let rawMax = firstCapacityMah(in: allScopes, keys: ["AppleRawMaxCapacity", "NominalChargeCapacity"]),
               let rawCur = nonNegativeInt(in: allScopes, keys: ["AppleRawCurrentCapacity"]),
               rawMax > 0 {
                return min(max(Int((Double(rawCur) / Double(rawMax) * 100.0).rounded()), 0), 100)
            }
            return 0
        }()

        // MARK: - Design Capacity, Full-Charge Capacity & Battery Health (mAh)
        // Crucial: on Apple Silicon, top-level `MaxCapacity` is normalized to 100 (percent scale), NOT mAh.
        // We strictly require real mAh capacities to be > 100 to avoid ever treating percentage scale as mAh.
        let designCapacityMah = firstCapacityMah(in: allScopes, keys: ["DesignCapacity"])

        // Raw full-charge capacity (mAh) for display alongside DesignCapacity
        let rawMaxCapacityMah: Int? = {
            if let raw = firstCapacityMah(in: allScopes, keys: ["AppleRawMaxCapacity", "NominalChargeCapacity", "FccComp1", "FccComp2"]) {
                return raw
            }
            // Intel Macs expose real mAh directly in top-level `MaxCapacity` (> 100).
            if let intelMax = topMaxCap, intelMax > 100 {
                return intelMax
            }
            return nil
        }()

        // Compensated full-charge capacity used for Health % (tracks macOS System Settings closely).
        // `FccComp1` (compensated full-charge capacity) or `NominalChargeCapacity` matches Apple's
        // System Settings percentage much more closely than uncompensated raw capacity on Apple Silicon.
        let healthCapacityMah: Int? = {
            if let comp = firstCapacityMah(in: allScopes, keys: ["FccComp1", "NominalChargeCapacity", "AppleRawMaxCapacity", "FccComp2"]) {
                return comp
            }
            return rawMaxCapacityMah
        }()

        let currentCapacityMah: Int? = {
            if let rawCur = nonNegativeInt(in: allScopes, keys: ["AppleRawCurrentCapacity"]) {
                // Guard against normalized 0..100 values unless battery is genuinely near-empty (<= 2%).
                if rawCur > 100 || batteryPercent <= 2 {
                    return rawCur
                }
            }
            // Intel Mac where top-level MaxCapacity > 100 and CurrentCapacity is in mAh.
            if let maxCap = topMaxCap, maxCap > 100, let curCap = topCurCap {
                return curCap
            }
            // Derive cleanly from real full-charge mAh × batteryPercent so UI never displays "57 / 5954 mAh".
            if let maxMah = rawMaxCapacityMah {
                return Int((Double(batteryPercent) / 100.0 * Double(maxMah)).rounded())
            }
            return nil
        }()

        let batteryHealthPercent: Double? = {
            guard let design = designCapacityMah, design > 100,
                  let full = healthCapacityMah, full > 100 else {
                return nil
            }
            let ratio = (Double(full) / Double(design)) * 100.0
            // Clamp to 0...100 matching macOS System Settings Maximum Capacity display.
            return min(max(ratio, 0.0), 100.0)
        }()

        let cycleCount = nonNegativeInt(in: allScopes, keys: ["CycleCount"]) ?? 0
        let designCycleCount = positiveInt(in: allScopes, keys: ["DesignCycleCount9C", "DesignCycleCount"]) ?? 1000

        // MARK: - Pack Voltage & Signed Current (mV / mA)
        let voltageMv = positiveInt(in: allScopes, keys: ["Voltage", "AppleRawBatteryVoltage"]) ?? 0
        let voltageV = Double(voltageMv) / 1000.0

        // IOKit frequently stores negative InstantAmperage as 64-bit unsigned two's complement (e.g. 18446744073709550201 = -1415 mA).
        let instantAmperageMa = signedInt64Value(in: allScopes, keys: ["InstantAmperage", "Amperage"]) ?? 0
        let amperageA = Double(instantAmperageMa) / 1000.0
        let rawBatteryNetWatts = voltageV * amperageA

        // MARK: - PowerTelemetryData (Apple Silicon Live Power Split)
        let telemetryDict = (registryProps["PowerTelemetryData"] as? [String: Any])
            ?? (batteryPackProps["PowerTelemetryData"] as? [String: Any])
        let systemPowerInMw = positiveInt(in: telemetryDict.map { [$0] } ?? [], keys: ["SystemPowerIn"])
        let systemLoadMw = positiveInt(in: telemetryDict.map { [$0] } ?? [], keys: ["SystemLoad"])
        let systemVoltageInMv = positiveInt(in: telemetryDict.map { [$0] } ?? [], keys: ["SystemVoltageIn", "SystemInputVoltage"])
        let systemCurrentInMa = positiveInt(in: telemetryDict.map { [$0] } ?? [], keys: ["SystemCurrentIn", "SystemInputCurrent"])

        let rawAdapterVoltageV: Double? = systemVoltageInMv.map { Double($0) / 1000.0 }
        let rawAdapterCurrentA: Double? = systemCurrentInMa.map { Double($0) / 1000.0 }

        // MARK: - Adapter Hardware Details (negotiated max capability — kept separate from live draw)
        let adapterInfo = parseAdapterInfo(
            registryProps: registryProps,
            isExternalConnected: isExternalConnected,
            fallbackWatts: iopsFallback.adapterWatts
        )

        // MARK: - Mathematically Consistent Power Flow Calculation
        let batteryNetWatts: Double = {
            if !isExternalConnected {
                // Unplugged: battery can only discharge (never report positive charge while unplugged).
                return -abs(rawBatteryNetWatts)
            }
            return rawBatteryNetWatts
        }()

        let adapterInputWatts: Double = {
            guard isExternalConnected else { return 0.0 }
            if let powerInMw = systemPowerInMw {
                return Double(powerInMw) / 1000.0
            }
            if let v = rawAdapterVoltageV, let a = rawAdapterCurrentA {
                return v * a
            }
            if let loadMw = systemLoadMw {
                return max(Double(loadMw) / 1000.0 + batteryNetWatts, 0.0)
            }
            return max(batteryNetWatts, 0.0)
        }()

        let systemLoadWatts: Double = {
            if !isExternalConnected {
                // On battery, prefer SystemLoad if available, else pack discharge watts; keep unified with battery draw.
                if let loadMw = systemLoadMw {
                    return Double(loadMw) / 1000.0
                }
                return abs(batteryNetWatts)
            }

            if let loadMw = systemLoadMw {
                return Double(loadMw) / 1000.0
            }
            // Conservation of power: Mac load = Charger In - Battery Net (note: when battery drains, subtracting negative adds its assist).
            return max(adapterInputWatts - batteryNetWatts, 0.0)
        }()

        // Live input V & A: ONLY populate when physically consistent with live `adapterInputWatts`!
        // Never leak the adapter's static negotiated MAX current (e.g. 5.0A) as live current.
        let (liveAdapterVoltageV, liveAdapterCurrentA): (Double?, Double?) = {
            guard isExternalConnected, adapterInputWatts > 0.1 else { return (nil, nil) }
            if let v = rawAdapterVoltageV, v > 1.0 {
                if let a = rawAdapterCurrentA, a > 0.01 {
                    return (v, a)
                }
                // Derive live current from actual SystemPowerIn / SystemVoltageIn so V × A == W.
                return (v, adapterInputWatts / v)
            }
            return (nil, nil)
        }()

        // MARK: - Battery Temperature & Cell Voltages
        let temperatureC = parseTemperatureCelsius(scopes: allScopes)

        let cellVoltagesMv: [Int] = {
            for scope in [batteryData, packBatteryData, registryProps, batteryPackProps] {
                if let cells = scope["CellVoltage"] as? [NSNumber] {
                    let valid = cells.map(\.intValue).filter { $0 > 500 && $0 < 6000 }
                    if !valid.isEmpty { return valid }
                }
            }
            return []
        }()

        // MARK: - Effective Charging State & Time Remaining
        let effectivelyCharging = isExternalConnected && (isChargingFlag || batteryNetWatts > 0.5) && batteryNetWatts >= -0.2

        let timeRemainingMinutes: Int? = {
            if effectivelyCharging {
                let raw = positiveInt(in: allScopes, keys: ["AvgTimeToFull", "InstantTimeToFull"]) ?? iopsFallback.timeToFull
                if let val = raw, val > 0, val < 65535 { return val }
            } else if !isExternalConnected {
                let raw = positiveInt(in: allScopes, keys: ["AvgTimeToEmpty", "TimeRemaining"]) ?? iopsFallback.timeToEmpty
                if let val = raw, val > 0, val < 65535 { return val }
            }
            return nil
        }()

        let phase = classifyPhase(
            isExternalConnected: isExternalConnected,
            isCharging: effectivelyCharging,
            isFullyCharged: isFullyCharged,
            batteryPercent: batteryPercent,
            batteryNetWatts: batteryNetWatts,
            adapterInputWatts: adapterInputWatts
        )

        return PowerTelemetry(
            timestamp: now,
            adapterInputWatts: adapterInputWatts,
            batteryNetWatts: batteryNetWatts,
            systemLoadWatts: systemLoadWatts,
            voltageV: voltageV,
            amperageA: amperageA,
            adapterVoltageV: liveAdapterVoltageV,
            adapterCurrentA: liveAdapterCurrentA,
            batteryPercent: batteryPercent,
            isExternalConnected: isExternalConnected,
            isCharging: effectivelyCharging,
            isFullyCharged: isFullyCharged,
            phase: phase,
            timeRemainingMinutes: timeRemainingMinutes,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            designCapacityMah: designCapacityMah,
            maxCapacityMah: rawMaxCapacityMah,
            currentCapacityMah: currentCapacityMah,
            batteryHealthPercent: batteryHealthPercent,
            temperatureC: temperatureC,
            cellVoltagesMv: cellVoltagesMv,
            thermalLevel: thermalLevel,
            isLowPowerMode: isLowPowerMode,
            adapter: adapterInfo
        )
    }

    // MARK: - Temperature Parsing (Handles VirtualTemperature, deci-Kelvin, and centi-Kelvin)

    /// Parses battery temperature in Celsius across all macOS / Apple Silicon / Intel formats:
    /// - `VirtualTemperature` (Apple Silicon): centi-Celsius (e.g. `2985` -> `29.85°C`)
    /// - `Temperature` (macOS `AppleSmartBattery.cpp` SMBus): deci-Kelvin (e.g. `2985` -> `298.5 K` -> `25.35°C`)
    ///   or centi-Kelvin when `> 20_000` (e.g. `29850` -> `25.35°C`)
    public static func parseTemperatureCelsius(scopes: [[String: Any]]) -> Double? {
        // 1. Prefer `VirtualTemperature` (centi-Celsius on Apple Silicon, most consistent across macOS 14-27)
        if let rawVirtual = positiveInt(in: scopes, keys: ["VirtualTemperature"]) {
            if let c = convertVirtualTemperatureToCelsius(rawVirtual) {
                return c
            }
        }

        // 2. Fallback to `Temperature` / `BatteryTemperature` (deci-Kelvin or centi-Kelvin)
        if let rawTemp = positiveInt(in: scopes, keys: ["Temperature", "BatteryTemperature"]) {
            if let c = convertSmartBatteryTemperatureToCelsius(rawTemp) {
                return c
            }
        }

        return nil
    }

    private static func convertVirtualTemperatureToCelsius(_ raw: Int) -> Double? {
        if raw > 20_000 {
            let c = (Double(raw) / 100.0) - 273.15
            return (0.0...95.0).contains(c) ? c : nil
        }
        let centiC = Double(raw) / 100.0
        if (0.0...95.0).contains(centiC) {
            return centiC
        }
        return nil
    }

    private static func convertSmartBatteryTemperatureToCelsius(_ raw: Int) -> Double? {
        // Centi-Kelvin (e.g. 29815 = 298.15 K = 25.0°C)
        if raw > 20_000 {
            let c = (Double(raw) / 100.0) - 273.15
            return (0.0...95.0).contains(c) ? c : nil
        }
        // Standard macOS SMBus deci-Kelvin (e.g. 2985 = 298.5 K = 25.35°C; range 2731...3681 -> 0...95°C)
        if (2731...3681).contains(raw) {
            return (Double(raw) / 10.0) - 273.15
        }
        // Centi-Celsius fallback (e.g. 2219 = 22.19°C when outside Kelvin range)
        let centiC = Double(raw) / 100.0
        if (0.0...95.0).contains(centiC) {
            return centiC
        }
        return nil
    }

    // MARK: - Private IOKit Registry Readers

    private static func readBatteryRegistryDictionaries() -> (smartBattery: [String: Any], batteryPack: [String: Any]) {
        let smartBattery = readProperties(forServiceNamed: "AppleSmartBattery")
        var batteryPack = readProperties(forServiceNamed: "AppleSmartBatteryPack")

        // If AppleSmartBatteryPack wasn't matched directly, inspect child entries of AppleSmartBattery.
        if batteryPack.isEmpty {
            batteryPack = readChildProperties(ofServiceNamed: "AppleSmartBattery")
        }

        return (smartBattery, batteryPack)
    }

    private static func readProperties(forServiceNamed name: String) -> [String: Any] {
        guard let matching = IOServiceMatching(name) else { return [:] }
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

    private static func readChildProperties(ofServiceNamed name: String) -> [String: Any] {
        guard let matching = IOServiceMatching(name) else { return [:] }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(service) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var child = IOIteratorNext(iterator)
        while child != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(iterator)
            }
            var unmanagedProps: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(child, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = unmanagedProps?.takeRetainedValue() as? [String: Any],
               props["BatteryData"] != nil || props["DesignCapacity"] != nil || props["Temperature"] != nil {
                return props
            }
        }
        return [:]
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

    private static func parseAdapterInfo(
        registryProps: [String: Any],
        isExternalConnected: Bool,
        fallbackWatts: Int?
    ) -> AdapterHardwareInfo? {
        guard isExternalConnected else { return nil }

        let details = registryProps["AdapterDetails"] as? [String: Any]
            ?? (registryProps["AppleRawAdapterDetails"] as? [[String: Any]])?.first

        let watts = positiveInt(in: details.map { [$0] } ?? [], keys: ["Watts"]) ?? fallbackWatts ?? 0
        let voltageMv = positiveInt(in: details.map { [$0] } ?? [], keys: ["AdapterVoltage"])
        let currentMa = positiveInt(in: details.map { [$0] } ?? [], keys: ["Current"])
        let negotiatedV = voltageMv.map { Double($0) / 1000.0 }
        let negotiatedA = currentMa.map { Double($0) / 1000.0 }

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
        if batteryNetWatts < -0.5 {
            return .batteryAssisting
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

    // MARK: - Safe Dictionary Extraction Helpers

    private static func firstCapacityMah(in scopes: [[String: Any]], keys: [String]) -> Int? {
        for key in keys {
            for scope in scopes {
                if let val = intValue(scope, key: key), val > 100 {
                    return val
                }
            }
        }
        return nil
    }

    private static func positiveInt(in scopes: [[String: Any]], keys: [String]) -> Int? {
        for key in keys {
            for scope in scopes {
                if let val = intValue(scope, key: key), val > 0 {
                    return val
                }
            }
        }
        return nil
    }

    private static func nonNegativeInt(in scopes: [[String: Any]], keys: [String]) -> Int? {
        for key in keys {
            for scope in scopes {
                if let val = intValue(scope, key: key), val >= 0 {
                    return val
                }
            }
        }
        return nil
    }

    private static func signedInt64Value(in scopes: [[String: Any]], keys: [String]) -> Int64? {
        for key in keys {
            for scope in scopes {
                if let val = signedInt64Value(scope, key: key) {
                    return val
                }
            }
        }
        return nil
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
