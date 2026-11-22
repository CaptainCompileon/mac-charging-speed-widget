import Foundation
import XCTest

final class PowerTelemetryTests: XCTestCase {

    // MARK: - 1. Temperature Parsing Across All macOS Formats

    func testVirtualTemperatureCentiCelsiusTakesPriority() throws {
        // Real Apple Silicon snapshot: Temperature is deci-Kelvin (2985 -> 25.35°C) while VirtualTemperature is centi-Celsius (3045 -> 30.45°C).
        let props: [String: Any] = [
            "Temperature": 2985,
            "VirtualTemperature": 3045
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        let tempC = try XCTUnwrap(telemetry.temperatureC)
        XCTAssertEqual(tempC, 30.45, accuracy: 0.01)
        XCTAssertEqual(telemetry.formattedTemperature(useFahrenheit: false), "30.4°C")
        XCTAssertEqual(telemetry.formattedTemperature(useFahrenheit: true), "86.8°F")
    }

    func testTopLevelZeroTemperatureFallsBackToNestedVirtualTemperature() {
        // Regression test: previously Temperature = 0 stopped the ?? chain and returned nil ("—").
        let props: [String: Any] = [
            "Temperature": 0,
            "BatteryData": [
                "VirtualTemperature": 3120
            ]
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        XCTAssertEqual(telemetry.temperatureC ?? -1, 31.20, accuracy: 0.01)
    }

    func testDeciKelvinSmartBatteryTemperatureConversion() {
        // AppleSmartBattery.cpp SMBus format: 2985 = 298.5 K = 25.35°C
        let props: [String: Any] = [
            "Temperature": 2985
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        XCTAssertEqual(telemetry.temperatureC ?? -1, 25.35, accuracy: 0.01)
    }

    func testCentiKelvinTemperatureConversion() {
        // 30455 centi-Kelvin = 304.55 K = 31.40°C
        let props: [String: Any] = [
            "Temperature": 30455
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        XCTAssertEqual(telemetry.temperatureC ?? -1, 31.40, accuracy: 0.01)
    }

    func testMacOS27ChildBatteryPackTemperature() {
        // macOS 27 moved detailed BatteryData fields into child AppleSmartBatteryPack node.
        let rootProps: [String: Any] = [
            "ExternalConnected": true,
            "CurrentCapacity": 80,
            "MaxCapacity": 100
        ]
        let packProps: [String: Any] = [
            "BatteryData": [
                "VirtualTemperature": 2890
            ]
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: rootProps, batteryPackProps: packProps)
        XCTAssertEqual(telemetry.temperatureC ?? -1, 28.90, accuracy: 0.01)
    }

    func testMissingOrInvalidTemperatureReturnsNilGracefully() {
        let props: [String: Any] = [
            "Temperature": 0,
            "VirtualTemperature": 0
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        XCTAssertNil(telemetry.temperatureC)
        XCTAssertEqual(telemetry.formattedTemperature(useFahrenheit: false), "—")
    }

    // MARK: - 2. Battery Health & Capacity Accuracy (Apple Silicon, macOS 26/27, Intel)

    func testAppleSiliconNormalizedMaxCapacityNeverTreatedAsMah() {
        // Real Apple Silicon regression:
        // Top-level MaxCapacity = 100 (percent scale!), CurrentCapacity = 57 (percent!),
        // while actual mAh lives inside BatteryData.
        let props: [String: Any] = [
            "MaxCapacity": 100,
            "CurrentCapacity": 57,
            "CycleCount": 628,
            "BatteryData": [
                "DesignCapacity": 4629,
                "AppleRawMaxCapacity": 3798,
                "NominalChargeCapacity": 3925,
                "FccComp1": 4120
            ]
        ]

        let telemetry = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(telemetry.batteryPercent, 57)
        XCTAssertEqual(telemetry.designCapacityMah, 4629)
        XCTAssertEqual(telemetry.maxCapacityMah, 3798, "Raw full-charge capacity must come from AppleRawMaxCapacity, never 100")
        XCTAssertEqual(telemetry.currentCapacityMah, Int((0.57 * 3798.0).rounded()), "Current mAh must be derived in mAh, never raw percent 57")
        // Health uses compensated FccComp1 (4120 / 4629 = 89.0%) matching System Settings
        XCTAssertEqual(telemetry.batteryHealthPercent ?? -1, (4120.0 / 4629.0) * 100.0, accuracy: 0.1)
        XCTAssertEqual(telemetry.formattedHealthPercent, "89%")
        XCTAssertEqual(telemetry.cycleCount, 628)
    }

    func testMacOS27ChildBatteryPackCapacitiesAndCells() {
        let rootProps: [String: Any] = [
            "MaxCapacity": 100,
            "CurrentCapacity": 80,
            "CycleCount": 73,
            "ExternalConnected": true,
            "IsCharging": false
        ]
        let packProps: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": 8579,
                "AppleRawMaxCapacity": 8238,
                "NominalChargeCapacity": 8482,
                "FccComp1": 8500,
                "CellVoltage": [NSNumber(value: 4118), NSNumber(value: 4121), NSNumber(value: 4119)]
            ]
        ]

        let telemetry = IOKitPowerReader.parse(registryProps: rootProps, batteryPackProps: packProps)

        XCTAssertEqual(telemetry.batteryPercent, 80)
        XCTAssertEqual(telemetry.designCapacityMah, 8579)
        XCTAssertEqual(telemetry.maxCapacityMah, 8238)
        XCTAssertEqual(telemetry.batteryHealthPercent ?? -1, (8500.0 / 8579.0) * 100.0, accuracy: 0.1)
        XCTAssertEqual(telemetry.cellVoltagesMv, [4118, 4121, 4119])
        XCTAssertEqual(telemetry.cellDeltaMv, 3)
    }

    func testIntelMacCapacityLayout() {
        // Intel Macs expose real mAh directly in MaxCapacity and CurrentCapacity without AppleRaw* keys.
        let props: [String: Any] = [
            "DesignCapacity": 5800,
            "MaxCapacity": 5100,
            "CurrentCapacity": 2550,
            "CycleCount": 310
        ]

        let telemetry = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(telemetry.batteryPercent, 50)
        XCTAssertEqual(telemetry.designCapacityMah, 5800)
        XCTAssertEqual(telemetry.maxCapacityMah, 5100)
        XCTAssertEqual(telemetry.currentCapacityMah, 2550)
        XCTAssertEqual(telemetry.batteryHealthPercent ?? -1, (5100.0 / 5800.0) * 100.0, accuracy: 0.1)
    }

    func testNewBatteryHealthCappedAt100Percent() {
        let props: [String: Any] = [
            "MaxCapacity": 100,
            "CurrentCapacity": 90,
            "DesignCapacity": 6075,
            "AppleRawMaxCapacity": 6240
        ]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        XCTAssertEqual(telemetry.batteryHealthPercent ?? -1, 100.0, accuracy: 0.01)
        XCTAssertEqual(telemetry.formattedHealthPercent, "100%")
    }

    func testDesktopMacWithoutBatteryDoesNotFabricate5000Mah() {
        let props: [String: Any] = [:]
        let telemetry = IOKitPowerReader.parse(registryProps: props)
        XCTAssertNil(telemetry.designCapacityMah)
        XCTAssertNil(telemetry.maxCapacityMah)
        XCTAssertNil(telemetry.currentCapacityMah)
        XCTAssertNil(telemetry.batteryHealthPercent)
        XCTAssertEqual(telemetry.formattedHealthPercent, "—")
        XCTAssertEqual(telemetry.formattedMaxCapacity, "Unavailable")
    }

    // MARK: - 3. Power Flow Consistency & Signed 64-Bit Amperage

    func testFastChargingPowerFlowAndLiveVAConsistency() {
        let props: [String: Any] = [
            "ExternalConnected": true,
            "IsCharging": true,
            "FullyCharged": false,
            "MaxCapacity": 100,
            "CurrentCapacity": 78,
            "Voltage": 12680,
            "InstantAmperage": 5473, // +69.4W into battery
            "AvgTimeToFull": 28,
            "PowerTelemetryData": [
                "SystemPowerIn": 94200,   // 94.2W wall in
                "SystemLoad": 24800,      // 24.8W Mac load
                "SystemVoltageIn": 20000, // 20.0V
                "SystemCurrentIn": 4710   // 4.71A
            ],
            "AdapterDetails": [
                "Name": "140W USB-C Power Adapter",
                "Manufacturer": "Apple Inc.",
                "Watts": 140,
                "AdapterVoltage": 20000,
                "Current": 5000 // Max contract 5.0A — must NOT override live 4.71A
            ]
        ]

        let t = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(t.phase, .fastCharging)
        XCTAssertEqual(t.adapterInputWatts, 94.2, accuracy: 0.05)
        XCTAssertEqual(t.systemLoadWatts, 24.8, accuracy: 0.05)
        XCTAssertEqual(t.batteryNetWatts, 69.397, accuracy: 0.05)
        XCTAssertEqual(t.headlineWatts, 94.2, accuracy: 0.05)
        XCTAssertEqual(t.displayVoltageV, 20.0, accuracy: 0.01)
        XCTAssertEqual(t.displayCurrentA, 4.71, accuracy: 0.01)
        // V * A matches headline wattage
        XCTAssertEqual(t.displayVoltageV * t.displayCurrentA, t.headlineWatts, accuracy: 0.2)

        if case .charging(let chargerW, let macW, let batW) = t.powerFlowMode {
            XCTAssertEqual(chargerW, 94.2, accuracy: 0.05)
            XCTAssertEqual(macW, 24.8, accuracy: 0.05)
            XCTAssertEqual(batW, 69.4, accuracy: 0.1)
        } else {
            XCTFail("Expected .charging PowerFlowMode, got \(t.powerFlowMode)")
        }
    }

    func testStaticAdapterMaxCurrentNeverLeaksIntoLiveCurrent() {
        // When PowerTelemetryData reports SystemPowerIn + SystemVoltageIn but omits SystemCurrentIn,
        // live current must be derived as Power/Voltage (1.62A), NEVER the static 5.0A max contract!
        let props: [String: Any] = [
            "ExternalConnected": true,
            "IsCharging": true,
            "MaxCapacity": 100,
            "CurrentCapacity": 65,
            "Voltage": 12200,
            "InstantAmperage": 1000,
            "PowerTelemetryData": [
                "SystemPowerIn": 32400,
                "SystemLoad": 20200,
                "SystemVoltageIn": 20000
            ],
            "AdapterDetails": [
                "Watts": 140,
                "AdapterVoltage": 20000,
                "Current": 5000
            ]
        ]

        let t = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(t.displayVoltageV, 20.0, accuracy: 0.01)
        XCTAssertEqual(t.displayCurrentA, 1.62, accuracy: 0.02)
        XCTAssertEqual(t.displayVoltageV * t.displayCurrentA, t.adapterInputWatts, accuracy: 0.1)
        XCTAssertEqual(t.adapter?.negotiatedCurrentA, 5.0)
    }

    func testUnsigned64BitTwosComplementDischargingCurrentOnBattery() {
        // Real macOS ioreg value: 18446744073709550201 == Int64(-1415) mA
        let wrappedNegativeMa = NSNumber(value: UInt64(bitPattern: Int64(-1415)))
        let props: [String: Any] = [
            "ExternalConnected": false,
            "IsCharging": false,
            "MaxCapacity": 100,
            "CurrentCapacity": 64,
            "Voltage": 11509,
            "InstantAmperage": wrappedNegativeMa,
            "AvgTimeToEmpty": 285
        ]

        let t = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(t.phase, .discharging)
        XCTAssertEqual(t.adapterInputWatts, 0.0, accuracy: 0.001)
        XCTAssertEqual(t.amperageA, -1.415, accuracy: 0.001)
        XCTAssertEqual(t.batteryNetWatts, -16.285, accuracy: 0.05)
        XCTAssertEqual(t.systemLoadWatts, 16.285, accuracy: 0.05)
        XCTAssertEqual(t.headlineWatts, 16.285, accuracy: 0.05)
        XCTAssertEqual(t.displayVoltageV * t.displayCurrentA, t.headlineWatts, accuracy: 0.05)

        if case .onBattery(let macW) = t.powerFlowMode {
            XCTAssertEqual(macW, 16.285, accuracy: 0.05)
        } else {
            XCTFail("Expected .onBattery PowerFlowMode, got \(t.powerFlowMode)")
        }
    }

    func testSlowChargerBatteryAssistingState() {
        // Plugged into a weak 20W charger while Mac draws 35W -> battery discharges -15W to help.
        let wrappedNegativeMa = NSNumber(value: UInt64(bitPattern: Int64(-1250)))
        let props: [String: Any] = [
            "ExternalConnected": true,
            "IsCharging": false,
            "MaxCapacity": 100,
            "CurrentCapacity": 50,
            "Voltage": 12000,
            "InstantAmperage": wrappedNegativeMa, // -15.0W
            "PowerTelemetryData": [
                "SystemPowerIn": 20000,
                "SystemLoad": 35000
            ]
        ]

        let t = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(t.phase, .batteryAssisting)
        XCTAssertFalse(t.isCharging)
        if case .batteryAssistingCharger(let chargerW, let assistW, let macW) = t.powerFlowMode {
            XCTAssertEqual(chargerW, 20.0, accuracy: 0.05)
            XCTAssertEqual(assistW, 15.0, accuracy: 0.05)
            XCTAssertEqual(macW, 35.0, accuracy: 0.05)
        } else {
            XCTFail("Expected .batteryAssistingCharger, got \(t.powerFlowMode)")
        }
    }

    func testOptimizedHoldACPassthrough() {
        let props: [String: Any] = [
            "ExternalConnected": true,
            "IsCharging": false,
            "FullyCharged": false,
            "MaxCapacity": 100,
            "CurrentCapacity": 80,
            "Voltage": 12360,
            "InstantAmperage": 0,
            "PowerTelemetryData": [
                "SystemPowerIn": 18400,
                "SystemLoad": 18400
            ]
        ]

        let t = IOKitPowerReader.parse(registryProps: props)

        XCTAssertEqual(t.phase, .optimizedHold)
        if case .acPassthrough(let chargerW, let macW) = t.powerFlowMode {
            XCTAssertEqual(chargerW, 18.4, accuracy: 0.05)
            XCTAssertEqual(macW, 18.4, accuracy: 0.05)
        } else {
            XCTFail("Expected .acPassthrough, got \(t.powerFlowMode)")
        }
    }

    // MARK: - 4. UpdateManager Semantic Version Comparison

    func testSemanticVersionComparison() {
        XCTAssertTrue(UpdateManager.isVersion("1.2.0", newerThan: "1.1.0"))
        XCTAssertTrue(UpdateManager.isVersion("v1.1.2", newerThan: "1.1.1"))
        XCTAssertTrue(UpdateManager.isVersion("2.0.0", newerThan: "1.9.9"))
        XCTAssertFalse(UpdateManager.isVersion("1.1.0", newerThan: "1.1.0"))
        XCTAssertFalse(UpdateManager.isVersion("1.0.9", newerThan: "1.1.0"))
        XCTAssertEqual(UpdateManager.normalizeVersion("  v1.1.1 "), "1.1.1")
    }
}
