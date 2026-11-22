import SwiftUI

/// Adaptive Apple Liquid Glass styling.
/// Uses native macOS 26 Tahoe `.glassEffect` & `GlassEffectContainer` when compiled with
/// Xcode 26+ and running on macOS 26+, and renders a hand-crafted specular vibrancy glass
/// surface on macOS 14 Sonoma & macOS 15 Sequoia.
public enum GlassSurfaceRole {
    case tile
    case capsule
    case prominentTint(Color)
}

public struct AdaptiveLiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let role: GlassSurfaceRole
    let isInteractive: Bool

    public init(cornerRadius: CGFloat = 14, role: GlassSurfaceRole = .tile, isInteractive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.role = role
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            nativeLiquidGlass(content)
        } else {
            vibrancyFallback(content)
        }
        #else
        vibrancyFallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    @ViewBuilder
    private func nativeLiquidGlass(_ content: Content) -> some View {
        switch role {
        case .tile:
            let style: Glass = isInteractive ? .regular.interactive() : .regular
            content.glassEffect(style, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .capsule:
            let style: Glass = isInteractive ? .regular.interactive() : .regular
            content.glassEffect(style, in: Capsule())
        case .prominentTint(let tintColor):
            let base = Glass.regular.tint(tintColor.opacity(0.22))
            let style: Glass = isInteractive ? base.interactive() : base
            content.glassEffect(style, in: Capsule())
        }
    }
    #endif

    @ViewBuilder
    private func vibrancyFallback(_ content: Content) -> some View {
        switch role {
        case .tile:
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                }
        case .capsule:
            content
                .background {
                    Capsule().fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                }
        case .prominentTint(let tintColor):
            content
                .background {
                    Capsule()
                        .fill(tintColor.opacity(0.18))
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .overlay {
                    Capsule().strokeBorder(tintColor.opacity(0.36), lineWidth: 0.75)
                }
        }
    }
}

/// Groups multiple Liquid Glass elements into a single `GlassEffectContainer` on macOS 26+.
public struct AdaptiveGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    func liquidGlassTile(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        modifier(AdaptiveLiquidGlassModifier(cornerRadius: cornerRadius, role: .tile, isInteractive: interactive))
    }

    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        let role: GlassSurfaceRole = tint.map { .prominentTint($0) } ?? .capsule
        return modifier(AdaptiveLiquidGlassModifier(cornerRadius: 99, role: role, isInteractive: interactive))
    }
}

/// Apple semantic power accent colors.
public enum PowerPalette {
    public static let chargeGreen = Color(red: 0.20, green: 0.84, blue: 0.48)
    public static let systemBlue = Color(red: 0.26, green: 0.67, blue: 1.00)
    public static let cautionAmber = Color(red: 1.00, green: 0.72, blue: 0.22)
    public static let thermalRed = Color(red: 1.00, green: 0.36, blue: 0.34)
    public static let neutralGlass = Color.secondary

    public static func accent(for phase: ChargingPhase) -> Color {
        switch phase {
        case .fastCharging, .charging, .full:
            return chargeGreen
        case .trickleCharging, .optimizedHold, .batteryAssisting:
            return cautionAmber
        case .acPassthrough:
            return systemBlue
        case .discharging:
            return systemBlue
        }
    }

    public static func thermalColor(for level: SystemThermalLevel) -> Color {
        switch level {
        case .nominal: return chargeGreen
        case .fair: return cautionAmber
        case .serious, .critical: return thermalRed
        }
    }
}
