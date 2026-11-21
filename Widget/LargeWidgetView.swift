import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: ChargingSpeedEntry

    private var t: PowerTelemetry { entry.telemetry }
    private var accent: Color { PowerPalette.accent(for: t.phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Header + Live Hero Readout
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", t.headlineWatts))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text("W")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(headerSubtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 5) {
                        Label(t.phase.shortLabel, systemImage: t.phase.symbolName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(accent.opacity(0.15), in: Capsule())
                            .widgetAccentable()

                        Button(intent: RefreshTelemetryIntent()) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.07), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("\(t.batteryPercent)% · \(t.etaDescription)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Real-time Charging Curve Chart
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Charging Curve")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f V · %.2f A", t.displayVoltageV, t.displayCurrentA))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                PowerSparklineView(
                    points: entry.history,
                    accentColor: accent,
                    showGrid: true,
                    showPeakLabel: true
                )
                .frame(maxHeight: .infinity)
                .widgetAccentable()
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Power Flow Split
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Power Flow")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let util = t.adapterUtilization, let maxW = t.adapter?.maxWatts {
                        Text(String(format: "%.0f%% of %dW", util * 100, maxW))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                PowerFlowBarView(telemetry: t, compact: false)
            }

            // Bottom Health, Cycles & Thermals Tiles
            HStack(spacing: 8) {
                statCard(
                    label: "Health",
                    value: String(format: "%.0f%%", t.batteryHealthPercent),
                    detail: "\(t.maxCapacityMah) mAh"
                )
                statCard(
                    label: "Cycles",
                    value: "\(t.cycleCount)",
                    detail: "of \(t.designCycleCount)"
                )
                statCard(
                    label: "Temp",
                    value: t.formattedTemperature(useFahrenheit: entry.useFahrenheit),
                    detail: t.thermalLevel.rawValue
                )
            }
        }
        .padding(2)
    }

    private var headerSubtitle: String {
        if let adapter = t.adapter {
            return "\(adapter.name) · \(adapter.protocolDescription)"
        }
        if let delta = t.cellDeltaMv {
            return "Internal Battery · Cell Δ \(delta) mV"
        }
        return "Internal Battery · \(t.thermalLevel.rawValue) Thermal"
    }

    private func statCard(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
        }
    }
}
