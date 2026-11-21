import AppKit
import SwiftUI

/// Native macOS Software Update prompt designed for cold start and manual checks.
/// Follows Impeccable Operate + Apple HIG standards: clear state hierarchy, real byte progress,
/// native controls, semantic surfaces, and inline automatic-update preference control.
struct UpdatePromptView: View {
    @Bindable var updater: UpdateManager
    let isColdStart: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 16)

            stateContentSection
                .padding(.horizontal, 22)
                .padding(.bottom, 18)

            Divider()
                .opacity(0.45)

            preferencesBar
                .padding(.horizontal, 22)
                .padding(.vertical, 13)

            Divider()
                .opacity(0.45)

            actionFooter
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(width: 448)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            appIconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(headlineText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var appIconBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "bolt.circle.fill")
                        .resizable()
                        .foregroundStyle(PowerPalette.chargeGreen)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            statusBadgeIcon
                .offset(x: 4, y: 4)
        }
    }

    @ViewBuilder
    private var statusBadgeIcon: some View {
        switch updater.state {
        case .available, .readyToInstall, .downloading:
            Image(systemName: "arrow.down.circle.fill")
                .symbolRenderingMode(.palette)
                .font(.system(size: 18))
                .foregroundStyle(.white, PowerPalette.chargeGreen)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        case .upToDate, .installerOpened:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .font(.system(size: 18))
                .foregroundStyle(.white, PowerPalette.chargeGreen)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .font(.system(size: 17))
                .foregroundStyle(.white, PowerPalette.cautionAmber)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        case .idle, .checking:
            EmptyView()
        }
    }

    private var headlineText: String {
        switch updater.state {
        case .idle, .checking:
            return "Checking for Updates…"
        case .upToDate:
            return "MacChargingSpeed is Up to Date"
        case .available(let release):
            return "MacChargingSpeed \(release.version) is Available"
        case .downloading(let release, _, _, _):
            return "Downloading Version \(release.version)"
        case .readyToInstall(let release, _):
            return "Version \(release.version) is Ready to Install"
        case .installerOpened(let release, _):
            return "Installer Opened for \(release.version)"
        case .failed(let title, _, _):
            return title
        }
    }

    private var subtitleText: String {
        switch updater.state {
        case .idle, .checking:
            return "Installed version \(updater.currentVersion) (build \(updater.currentBuild)). Contacting GitHub Releases."
        case .upToDate(let latest):
            return "You’re running version \(updater.currentVersion) — the latest release (\(latest))."
        case .available(let release):
            var parts = ["You have \(updater.currentVersion)"]
            if let date = release.formattedPublishedDate { parts.append("Released \(date)") }
            if let size = release.formattedSize { parts.append(size) }
            return parts.joined(separator: " · ")
        case .downloading(_, _, let written, let total):
            let writtenStr = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
            if total > 0 {
                let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                return "\(writtenStr) of \(totalStr)"
            }
            return "Downloaded \(writtenStr)…"
        case .readyToInstall(let release, _):
            let sizeNote = release.formattedSize.map { " (\($0))" } ?? ""
            return "Downloaded in the background\(sizeNote). Ready whenever you want to update."
        case .installerOpened:
            return "Drag MacChargingSpeed into Applications to finish updating, then relaunch."
        case .failed(_, let detail, _):
            return detail
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContentSection: some View {
        switch updater.state {
        case .idle, .checking:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking github.com/\(UpdateManager.repositorySlug)…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)

        case .upToDate:
            HStack(spacing: 12) {
                versionPill(label: "Installed", value: "v\(updater.currentVersion)", accent: PowerPalette.chargeGreen)
                if let checked = updater.lastCheckedDate {
                    versionPill(
                        label: "Checked",
                        value: checked.formatted(date: .omitted, time: .shortened),
                        accent: .secondary
                    )
                }
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                versionTransitionRow(from: updater.currentVersion, to: release.version)
                releaseNotesBox(release.notes)
            }

        case .readyToInstall(let release, _):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    versionTransitionRow(from: updater.currentVersion, to: release.version)
                    Spacer()
                    Label("Pre-downloaded", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PowerPalette.chargeGreen)
                }
                releaseNotesBox(release.notes)
            }

        case .downloading(_, let progress, _, let total):
            VStack(alignment: .leading, spacing: 8) {
                if total > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(PowerPalette.chargeGreen)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(PowerPalette.chargeGreen)
                }

                HStack {
                    Text(total > 0 ? String(format: "%.0f%% complete", progress * 100) : "Downloading release package…")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text("macOS Universal DMG")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)

        case .installerOpened:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        updater.revealDownloadedInstaller()
                    } label: {
                        Label("Show Disk Image", systemImage: "externaldrive.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        updater.copyTerminalUpdateCommand()
                        copiedCommand = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedCommand = false
                        }
                    } label: {
                        Label(
                            copiedCommand ? "Copied Command" : "Copy 1-Line Terminal Updater",
                            systemImage: copiedCommand ? "checkmark" : "terminal"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

        case .failed:
            EmptyView()
        }
    }

    private func versionPill(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private func versionTransitionRow(from current: String, to next: String) -> some View {
        HStack(spacing: 8) {
            Text("v\(current)")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text("v\(next)")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PowerPalette.chargeGreen)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(PowerPalette.chargeGreen.opacity(0.14), in: Capsule())
        }
    }

    private func releaseNotesBox(_ notes: String) -> some View {
        ScrollView {
            Text(notes)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(minHeight: 72, maxHeight: 132)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
    }

    // MARK: - Inline Automatic Updates Toggle

    private var preferencesBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic background updates")
                    .font(.system(size: 12.5, weight: .medium))
                Text(
                    updater.automaticUpdatesEnabled
                        ? "Checks every \(updater.checkIntervalHours) hours and pre-downloads new releases."
                        : "Background checks paused. You’ll still be prompted on launch."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("Automatic background updates", isOn: $updater.automaticUpdatesEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: - Action Footer

    private var actionFooter: some View {
        HStack(spacing: 10) {
            switch updater.state {
            case .idle, .checking:
                Spacer()
                Button("Hide") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

            case .upToDate:
                Button("Check Again") {
                    Task { await updater.checkForUpdates(isBackground: false) }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(isColdStart ? "Continue" : "Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(PowerPalette.chargeGreen)
                .keyboardShortcut(.defaultAction)

            case .available, .readyToInstall:
                Button("Release Notes") {
                    updater.openReleasesPage()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Not Now") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    Task { await updater.startUpdateNow() }
                }) {
                    Text(primaryUpdateButtonLabel)
                }
                .buttonStyle(.borderedProminent)
                .tint(PowerPalette.chargeGreen)
                .keyboardShortcut(.defaultAction)

            case .downloading:
                Spacer()
                Button("Cancel Download") {
                    updater.cancelActiveDownload()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            case .installerOpened:
                Spacer()
                Button("Quit to Replace App") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(PowerPalette.chargeGreen)
                .keyboardShortcut(.defaultAction)

                Button("Keep Running") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            case .failed(_, _, let recoveryURL):
                if recoveryURL != nil {
                    Button("Open Releases") {
                        updater.openReleasesPage()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Continue") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Try Again") {
                    Task { await updater.checkForUpdates(isBackground: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(PowerPalette.chargeGreen)
                .keyboardShortcut(.defaultAction)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: updater.state)
    }

    private var primaryUpdateButtonLabel: String {
        if case .readyToInstall = updater.state {
            return "Update Now"
        }
        return "Update Now"
    }
}
