import SwiftUI

/// Clear, scannable visualization of physical energy flow (Source → Destination)
/// across all four real-world Mac power states: Charging, AC Passthrough, Slow Charger, and On Battery.
public struct PowerFlowBarView: View {
    public let telemetry: PowerTelemetry
    public let compact: Bool

    public init(telemetry: PowerTelemetry, compact: Bool = false) {
        self.telemetry = telemetry
        self.compact = compact
    }

    public var body: some View {
        switch telemetry.powerFlowMode {
        case .charging(let chargerW, let macW, let batW):
            chargingView(chargerW: chargerW, macW: macW, batW: batW)
        case .acPassthrough(let chargerW, let macW):
            acPassthroughView(chargerW: chargerW, macW: macW)
        case .batteryAssistingCharger(let chargerW, let assistW, let macW):
            assistingView(chargerW: chargerW, assistW: assistW, macW: macW)
        case .onBattery(let macW):
            onBatteryView(macW: macW)
        }
    }

    // MARK: - State 1: Plugged In & Charging (Charger → Mac + Battery)

    private func chargingView(chargerW: Double, macW: Double, batW: Double) -> some View {
        let total = max(macW + batW, 0.1)
        let macShare = min(max(macW / total, 0.08), 0.92)
        let macPct = Int((macW / total * 100).rounded())
        let batPct = max(0, 100 - macPct)

        return VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                // Visual source -> destination equation
                HStack(spacing: 6) {
                    flowNode(icon: "powerplug.fill", title: "Charger", value: fmtW(chargerW), color: .primary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    flowNode(icon: "laptopcomputer", title: "Mac", value: fmtW(macW), color: PowerPalette.systemBlue)
                    Text("+")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    flowNode(icon: "battery.100percent.bolt", title: "Battery", value: "+\(fmtW(batW))", color: PowerPalette.chargeGreen)
                }
            }

            // Proportional split capsule
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let gap: CGFloat = 3
                let macWidth = max((w - gap) * macShare, 10)
                let batWidth = max(w - gap - macWidth, 10)
                HStack(spacing: gap) {
                    Capsule()
                        .fill(PowerPalette.systemBlue.gradient)
                        .frame(width: macWidth)
                    Capsule()
                        .fill(PowerPalette.chargeGreen.gradient)
                        .frame(width: batWidth)
                }
            }
            .frame(height: compact ? 6 : 8)
            .background(Color.primary.opacity(0.08), in: Capsule())

            // Clear legend with percentage share
            HStack(spacing: 8) {
                legendItem(
                    color: PowerPalette.systemBlue,
                    text: compact ? "Mac \(fmtW(macW))" : "Mac \(macPct)% (\(fmtW(macW)))"
                )
                Spacer(minLength: 4)
                legendItem(
                    color: PowerPalette.chargeGreen,
                    text: compact ? "Battery +\(fmtW(batW))" : "To Battery \(batPct)% (+\(fmtW(batW)))",
                    valueColor: PowerPalette.chargeGreen
                )
            }
        }
    }

    // MARK: - State 2: Plugged In, Battery Bypassed (Charger → Mac)

    private func acPassthroughView(chargerW: Double, macW: Double) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                HStack(spacing: 8) {
                    flowNode(icon: "powerplug.fill", title: "Charger", value: fmtW(chargerW), color: PowerPalette.systemBlue)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    flowNode(icon: "laptopcomputer", title: "Mac", value: fmtW(macW), color: PowerPalette.systemBlue)
                    Spacer()
                    Text("Battery idle")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            Capsule()
                .fill(PowerPalette.systemBlue.gradient)
                .frame(height: compact ? 6 : 8)

            HStack {
                legendItem(color: PowerPalette.systemBlue, text: "AC → Mac \(fmtW(macW))")
                Spacer(minLength: 4)
                Text("Battery idle (0W)")
                    .font(.system(size: compact ? 10 : 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - State 3: Weak Charger (Charger + Battery → Mac)

    private func assistingView(chargerW: Double, assistW: Double, macW: Double) -> some View {
        let total = max(chargerW + assistW, 0.1)
        let chargerShare = min(max(chargerW / total, 0.10), 0.90)

        return VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                HStack(spacing: 6) {
                    flowNode(icon: "powerplug.fill", title: "Charger", value: fmtW(chargerW), color: PowerPalette.systemBlue)
                    Text("+")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    flowNode(icon: "battery.50percent", title: "Battery", value: "−\(fmtW(assistW))", color: PowerPalette.cautionAmber)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    flowNode(icon: "laptopcomputer", title: "Mac", value: fmtW(macW), color: .primary)
                }
            }

            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let gap: CGFloat = 3
                let acWidth = max((w - gap) * chargerShare, 10)
                let batWidth = max(w - gap - acWidth, 10)
                HStack(spacing: gap) {
                    Capsule()
                        .fill(PowerPalette.systemBlue.gradient)
                        .frame(width: acWidth)
                    Capsule()
                        .fill(PowerPalette.cautionAmber.gradient)
                        .frame(width: batWidth)
                }
            }
            .frame(height: compact ? 6 : 8)
            .background(Color.primary.opacity(0.08), in: Capsule())

            HStack {
                legendItem(color: PowerPalette.systemBlue, text: "Charger \(fmtW(chargerW))")
                Spacer(minLength: 4)
                legendItem(
                    color: PowerPalette.cautionAmber,
                    text: "Battery −\(fmtW(assistW))",
                    valueColor: PowerPalette.cautionAmber
                )
            }
        }
    }

    // MARK: - State 4: Unplugged (Battery → Mac)

    private func onBatteryView(macW: Double) -> some View {
        let tier = PowerFlowMode.loadTier(for: macW)
        // Visual load bar scaled against a 45W portable workload reference
        let fillFraction = min(max(macW / 45.0, 0.08), 1.0)
        let barColor: Color = macW >= 30 ? PowerPalette.cautionAmber : PowerPalette.systemBlue

        return VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            if !compact {
                HStack(spacing: 8) {
                    flowNode(icon: "battery.75percent", title: "Battery", value: "\(telemetry.batteryPercent)%", color: barColor)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    flowNode(icon: "laptopcomputer", title: "Mac Draw", value: fmtW(macW), color: .primary)
                    Spacer()
                    Text("\(tier) load")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(barColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(barColor.opacity(0.14), in: Capsule())
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(barColor.gradient)
                        .frame(width: max(geo.size.width * fillFraction, 10))
                }
            }
            .frame(height: compact ? 6 : 8)

            HStack {
                legendItem(color: barColor, text: "Battery → Mac \(fmtW(macW))")
                Spacer(minLength: 4)
                Text(compact ? "\(tier) load" : telemetry.etaDescription)
                    .font(.system(size: compact ? 10 : 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Subcomponents

    private func flowNode(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .lineLimit(1)
    }

    private func legendItem(color: Color, text: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: compact ? 10 : 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func fmtW(_ watts: Double) -> String {
        String(format: "%.1fW", abs(watts))
    }
}
