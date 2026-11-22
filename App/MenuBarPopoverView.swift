import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var monitor: PowerMonitor
    @Bindable var updater: UpdateManager
    let onCheckUpdates: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var showHardwareDetails = false

    private var t: PowerTelemetry { monitor.telemetry }
    private var accent: Color { PowerPalette.accent(for: t.phase) }

    var body: some View {
        AdaptiveGlassGroup(spacing: 10) {
            VStack(spacing: 12) {
                headerRow
                if let release = updater.availableRelease {
                    updateAvailableBanner(release)
                }
                heroWattsCard
                powerFlowCard
                sparklineCard
                healthMetricsStrip
                adapterDetailsCard
                footerRow
            }
            .padding(14)
        }
        .frame(width: 344)
    }

    // MARK: - Update Available Banner

    private func updateAvailableBanner(_ release: AppRelease) -> some View {
        Button {
            onCheckUpdates()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PowerPalette.chargeGreen)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Version \(release.version) available")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isReadyInCache ? "Ready to install" : "Click to review and update")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Text("Update")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(PowerPalette.chargeGreen, in: Capsule())
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlassTile(cornerRadius: 12, interactive: true)
        .accessibilityLabel("Update available: version \(release.version)")
    }

    private var isReadyInCache: Bool {
        if case .readyToInstall = updater.state { return true }
        return false
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: t.phase.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .liquidGlassCapsule(tint: accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("MacChargingSpeed")
                    .font(.system(size: 13, weight: .semibold))
                Text(t.etaDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(t.phase.shortLabel)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .liquidGlassCapsule(tint: accent)
        }
    }

    // MARK: - Hero Watts Card

    private var heroWattsCard: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", t.headlineWatts))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("W")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                telemetryPill(label: String(format: "%.2f V", t.displayVoltageV), icon: "bolt.circle")
                telemetryPill(label: String(format: "%.2f A", t.displayCurrentA), icon: "waveform.path.ecg")
                telemetryPill(label: "\(t.batteryPercent)%", icon: "battery.100percent")
            }

            if let util = t.adapterUtilization, let maxW = t.adapter?.maxWatts {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(accent.gradient)
                                .frame(width: max(geo.size.width * util, 6))
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text(String(format: "%.0f%% of %dW charger headroom", util * 100, maxW))
                        Spacer()
                        Text(t.adapter?.protocolDescription ?? "USB-PD")
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .liquidGlassTile(cornerRadius: 16)
    }

    private func telemetryPill(label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    // MARK: - Power Flow Card

    private var powerFlowCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Power Flow")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(t.powerFlowMode.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            PowerFlowBarView(telemetry: t, compact: false)
        }
        .padding(12)
        .liquidGlassTile(cornerRadius: 14)
    }

    // MARK: - Live Charging Curve Card

    private var sparklineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Charging Curve")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("\(monitor.history.count) samples")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            PowerSparklineView(
                points: monitor.history,
                accentColor: accent,
                showGrid: true,
                showPeakLabel: true
            )
            .frame(height: 62)
        }
        .padding(12)
        .liquidGlassTile(cornerRadius: 14)
    }

    // MARK: - Battery Health & Thermals Strip

    private var healthMetricsStrip: some View {
        HStack(spacing: 8) {
            metricTile(
                title: "Health",
                value: t.formattedHealthPercent,
                subtitle: t.formattedMaxCapacity,
                icon: "heart.fill",
                tint: (t.batteryHealthPercent ?? 100) >= 85 ? PowerPalette.chargeGreen : PowerPalette.cautionAmber
            )
            metricTile(
                title: "Cycles",
                value: "\(t.cycleCount)",
                subtitle: "of \(t.designCycleCount)",
                icon: "arrow.triangle.2.circlepath",
                tint: PowerPalette.systemBlue
            )
            metricTile(
                title: t.temperatureC != nil ? "Temp" : "Thermal",
                value: t.temperatureC != nil
                    ? t.formattedTemperature(useFahrenheit: monitor.useFahrenheit)
                    : t.thermalLevel.rawValue,
                subtitle: t.temperatureC != nil ? t.thermalLevel.rawValue : "Sensor N/A",
                icon: "thermometer.medium",
                tint: PowerPalette.thermalColor(for: t.thermalLevel)
            )
        }
    }

    private func metricTile(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassTile(cornerRadius: 12)
    }

    // MARK: - Adapter & Cell Hardware Inspector

    private var adapterDetailsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    showHardwareDetails.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: t.isExternalConnected ? "powercord.fill" : "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(t.adapter?.name ?? "Internal Battery Pack")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    if t.isLowPowerMode {
                        Text("Low Power")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(PowerPalette.cautionAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PowerPalette.cautionAmber.opacity(0.16), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showHardwareDetails ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showHardwareDetails {
                Divider().opacity(0.3)

                VStack(spacing: 4) {
                    if let adapter = t.adapter {
                        detailRow("Protocol", adapter.protocolDescription)
                        if let mfg = adapter.manufacturer {
                            detailRow("Manufacturer", mfg)
                        }
                        if let v = adapter.negotiatedVoltageV, let a = adapter.negotiatedCurrentA {
                            detailRow("PD Contract", String(format: "%.1f V · %.2f A (%d W)", v, a, adapter.maxWatts))
                        }
                        if let serial = adapter.serialNumber {
                            detailRow("Serial", serial)
                        }
                    }

                    detailRow("Pack Voltage", String(format: "%.3f V (%.2f A)", t.voltageV, t.amperageA))
                    detailRow("Capacity", t.formattedCapacityDetail)

                    if !t.cellVoltagesMv.isEmpty {
                        let cells = t.cellVoltagesMv.map { String(format: "%.2fV", Double($0) / 1000.0) }.joined(separator: " · ")
                        let deltaText = t.cellDeltaMv.map { " (Δ \($0) mV)" } ?? ""
                        detailRow("Cells", cells + deltaText)
                    }

                    detailRow("Thermal State", t.thermalLevel.rawValue)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlassTile(cornerRadius: 12)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 10.5))
    }

    // MARK: - Footer Controls

    private var footerRow: some View {
        HStack(spacing: 6) {
            Picker("Menu Bar", selection: $monitor.menuBarMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 118)

            Spacer()

            Button {
                onCheckUpdates()
            } label: {
                Image(systemName: updater.hasUpdateAvailable ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(updater.hasUpdateAvailable ? PowerPalette.chargeGreen : .primary)
            }
            .buttonStyle(.borderless)
            .help("Check for updates")
            .accessibilityLabel("Check for updates")

            Button {
                monitor.refreshNow(forceWidgetReload: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Refresh telemetry & sync desktop widgets")
            .accessibilityLabel("Refresh telemetry")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Open settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Quit MacChargingSpeed")
            .accessibilityLabel("Quit MacChargingSpeed")
        }
        .padding(.top, 2)
    }
}
