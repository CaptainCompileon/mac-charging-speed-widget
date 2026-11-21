import SwiftUI

/// Visualizes how incoming adapter power is split between the Mac system load and net battery charging.
public struct PowerFlowBarView: View {
    public let telemetry: PowerTelemetry
    public let compact: Bool

    public init(telemetry: PowerTelemetry, compact: Bool = false) {
        self.telemetry = telemetry
        self.compact = compact
    }

    private var systemShare: Double {
        let sys = max(telemetry.systemLoadWatts, 0)
        let bat = max(telemetry.batteryNetWatts, 0)
        let total = sys + bat
        guard total > 0.1 else { return telemetry.isExternalConnected ? 1.0 : 1.0 }
        return min(max(sys / total, 0.08), 0.92)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            // Segmented capsule bar
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let gap: CGFloat = (telemetry.isExternalConnected && telemetry.batteryNetWatts > 0.2) ? 3 : 0

                if telemetry.isExternalConnected && telemetry.batteryNetWatts > 0.2 {
                    let sysW = max((width - gap) * systemShare, 8)
                    let batW = max(width - gap - sysW, 8)
                    HStack(spacing: gap) {
                        Capsule()
                            .fill(PowerPalette.systemBlue.gradient)
                            .frame(width: sysW)
                        Capsule()
                            .fill(PowerPalette.chargeGreen.gradient)
                            .frame(width: batW)
                    }
                } else if telemetry.isExternalConnected {
                    Capsule()
                        .fill(PowerPalette.systemBlue.gradient)
                } else {
                    Capsule()
                        .fill(PowerPalette.cautionAmber.gradient)
                }
            }
            .frame(height: compact ? 6 : 8)
            .background(Color.primary.opacity(0.08), in: Capsule())

            // Labels row
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(telemetry.isExternalConnected ? PowerPalette.systemBlue : PowerPalette.cautionAmber)
                        .frame(width: 6, height: 6)
                    Text(telemetry.isExternalConnected ? "System" : "Draw")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fW", telemetry.systemLoadWatts))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    Circle()
                        .fill(telemetry.batteryNetWatts >= 0 ? PowerPalette.chargeGreen : PowerPalette.cautionAmber)
                        .frame(width: 6, height: 6)
                    Text("Battery")
                        .foregroundStyle(.secondary)
                    Text(telemetry.formattedWatts(telemetry.batteryNetWatts, signed: true).replacingOccurrences(of: " W", with: "W"))
                        .fontWeight(.semibold)
                        .foregroundStyle(telemetry.batteryNetWatts >= 0 ? PowerPalette.chargeGreen : .primary)
                        .monospacedDigit()
                }
            }
            .font(.system(size: compact ? 10 : 11, weight: .regular, design: .rounded))
            .lineLimit(1)
        }
    }
}
