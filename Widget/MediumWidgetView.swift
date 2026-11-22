import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: ChargingSpeedEntry

    private var t: PowerTelemetry { entry.telemetry }
    private var accent: Color { PowerPalette.accent(for: t.phase) }

    var body: some View {
        HStack(spacing: 14) {
            // Left column: Hero wattage + V/A + Power Flow split
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: t.phase.symbolName)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(accent)
                        .widgetAccentable()
                    Text(t.phase.shortLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Button(intent: RefreshTelemetryIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", t.headlineWatts))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("W")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(String(format: "%.1fV · %.2fA · %d%%", t.displayVoltageV, t.displayCurrentA, t.batteryPercent))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 2)

                PowerFlowBarView(telemetry: t, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: Real-time Charging Curve sparkline + ETA + Health
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    if let maxW = t.adapter?.maxWatts, maxW > 0 {
                        Text("\(maxW)W PD")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    Text(t.temperatureC != nil ? t.formattedTemperature(useFahrenheit: entry.useFahrenheit) : t.thermalLevel.rawValue)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                PowerSparklineView(
                    points: entry.history,
                    accentColor: accent,
                    showGrid: false,
                    showPeakLabel: false
                )
                .frame(maxHeight: .infinity)
                .widgetAccentable()

                HStack(spacing: 6) {
                    Text(t.etaDescription)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if t.batteryHealthPercent != nil {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(t.formattedHealthPercent)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: 126)
        }
        .padding(2)
    }
}
