import SwiftUI

/// Smooth Apple-style real-time wattage sparkline with soft area gradient and glowing live node.
public struct PowerSparklineView: View {
    public let points: [PowerHistoryPoint]
    public let accentColor: Color
    public let showGrid: Bool
    public let showPeakLabel: Bool

    public init(
        points: [PowerHistoryPoint],
        accentColor: Color = PowerPalette.chargeGreen,
        showGrid: Bool = false,
        showPeakLabel: Bool = false
    ) {
        self.points = points
        self.accentColor = accentColor
        self.showGrid = showGrid
        self.showPeakLabel = showPeakLabel
    }

    private var values: [Double] {
        if points.count >= 2 {
            return points.map(\.totalWatts)
        }
        if let only = points.first {
            return [only.totalWatts, only.totalWatts]
        }
        return [0, 0]
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let data = values
            let peak = max(data.max() ?? 10, 10)
            let floorVal = max(0, (data.min() ?? 0) * 0.75)
            let span = max(peak - floorVal, 5.0)
            let topPad: CGFloat = 6
            let bottomPad: CGFloat = 4
            let usableH = max(h - topPad - bottomPad, 1)

            let coords: [CGPoint] = data.enumerated().map { idx, val in
                let x = data.count > 1 ? (CGFloat(idx) / CGFloat(data.count - 1)) * w : w
                let norm = CGFloat((val - floorVal) / span)
                let y = topPad + usableH * (1.0 - min(max(norm, 0), 1))
                return CGPoint(x: x, y: y)
            }

            ZStack(alignment: .topTrailing) {
                if showGrid {
                    gridOverlay(height: h)
                }

                // Soft gradient area fill
                areaPath(coords: coords, height: h)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.32),
                                accentColor.opacity(0.08),
                                accentColor.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Crisp curve stroke
                smoothLinePath(coords: coords)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                    )

                // Live terminal point
                if let last = coords.last {
                    Circle()
                        .fill(accentColor.opacity(0.28))
                        .frame(width: 10, height: 10)
                        .position(last)

                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .position(last)
                }

                if showPeakLabel, let maxW = data.max(), maxW > 0.5 {
                    Text(String(format: "Peak %.0fW", maxW))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func gridOverlay(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.22)
            Spacer()
            Divider().opacity(0.16)
            Spacer()
            Divider().opacity(0.22)
        }
        .frame(height: height)
    }

    private func smoothLinePath(coords: [CGPoint]) -> Path {
        var path = Path()
        guard let first = coords.first else { return path }
        path.move(to: first)
        guard coords.count > 1 else { return path }

        if coords.count == 2 {
            path.addLine(to: coords[1])
            return path
        }

        for i in 1..<coords.count {
            let prev = coords[i - 1]
            let curr = coords[i]
            let mid = CGPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
            if i == 1 {
                path.addLine(to: mid)
            } else {
                path.addQuadCurve(to: mid, control: prev)
            }
            if i == coords.count - 1 {
                path.addLine(to: curr)
            }
        }
        return path
    }

    private func areaPath(coords: [CGPoint], height: CGFloat) -> Path {
        var path = smoothLinePath(coords: coords)
        guard let first = coords.first, let last = coords.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}
