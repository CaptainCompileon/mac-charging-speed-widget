import AppIntents
import SwiftUI
import WidgetKit

/// Interactive AppIntent so users can refresh desktop widget telemetry on demand.
struct RefreshTelemetryIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Power Telemetry"
    static let description = IntentDescription("Reads live charging wattage, voltage, current, and battery health from IOKit.")

    func perform() async throws -> some IntentResult {
        let live = IOKitPowerReader.readCurrentTelemetry()
        TelemetryStore.shared.saveSnapshot(live, appendToHistory: true)
        WidgetCenter.shared.reloadTimelines(ofKind: "MacChargingSpeedWidget")
        return .result()
    }
}

struct ChargingSpeedEntry: TimelineEntry {
    let date: Date
    let telemetry: PowerTelemetry
    let history: [PowerHistoryPoint]
    let useFahrenheit: Bool
}

struct ChargingSpeedTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChargingSpeedEntry {
        ChargingSpeedEntry(
            date: Date(),
            telemetry: .previewFastCharge,
            history: PowerTelemetry.previewHistory,
            useFahrenheit: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ChargingSpeedEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(makeLiveEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChargingSpeedEntry>) -> Void) {
        let entry = makeLiveEntry()
        // Refresh every 2 minutes while charging, or every 5 minutes when idle/on battery.
        let refreshSeconds: TimeInterval = entry.telemetry.isCharging ? 120 : 300
        let nextRefresh = Date().addingTimeInterval(refreshSeconds)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeLiveEntry() -> ChargingSpeedEntry {
        let store = TelemetryStore.shared
        let live = IOKitPowerReader.readCurrentTelemetry()
        store.saveSnapshot(live, appendToHistory: true)

        var history = store.loadHistory()
        if history.count < 2 {
            history = [
                PowerHistoryPoint(
                    timestamp: live.timestamp.addingTimeInterval(-60),
                    totalWatts: live.headlineWatts,
                    batteryWatts: live.batteryNetWatts,
                    systemLoadWatts: live.systemLoadWatts,
                    batteryPercent: live.batteryPercent
                ),
                PowerHistoryPoint(
                    timestamp: live.timestamp,
                    totalWatts: live.headlineWatts,
                    batteryWatts: live.batteryNetWatts,
                    systemLoadWatts: live.systemLoadWatts,
                    batteryPercent: live.batteryPercent
                )
            ]
        }

        return ChargingSpeedEntry(
            date: live.timestamp,
            telemetry: live,
            history: history,
            useFahrenheit: store.useFahrenheit
        )
    }
}

struct ChargingSpeedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChargingSpeedEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                MediumWidgetView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        PowerPalette.accent(for: entry.telemetry.phase).opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct MacChargingSpeedWidget: Widget {
    let kind: String = "MacChargingSpeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChargingSpeedTimelineProvider()) { entry in
            ChargingSpeedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Charging Speed")
        .description("Live charging wattage, voltage, amperage, power flow split, charging curve, and battery health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
