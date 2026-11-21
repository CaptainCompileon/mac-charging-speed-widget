import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: ChargingSpeedEntry

    private var t: PowerTelemetry { entry.telemetry }
    private var accent: Color { PowerPalette.accent(for: t.phase) }

    var body: some View {
        ZStack {
            // Circular battery & power progress ring
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 8)

            Circle()
                .trim(from: 0, to: Double(t.batteryPercent) / 100.0)
                .stroke(
                    accent.gradient,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()

            VStack(spacing: 2) {
                Image(systemName: t.phase.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .widgetAccentable()

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(String(format: "%.1f", t.headlineWatts))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                    Text("W")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("\(t.batteryPercent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(String(format: "%.1fV · %.1fA", t.displayVoltageV, t.displayCurrentA))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(14)
        }
        .padding(4)
    }
}
