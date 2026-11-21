import AppKit
import Foundation
import Observation

/// Parsed GitHub Release metadata for an available MacChargingSpeed version.
public struct AppRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let version: String
    public let title: String
    public let notes: String
    public let publishedAt: Date?
    public let htmlURL: URL
    public let dmgDownloadURL: URL?
    public let zipDownloadURL: URL?
    public let assetSizeBytes: Int64?

    public var preferredDownloadURL: URL? {
        dmgDownloadURL ?? zipDownloadURL
    }

    public var formattedSize: String? {
        guard let bytes = assetSizeBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public var formattedPublishedDate: String? {
        guard let publishedAt else { return nil }
        return publishedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Lifecycle state of the updater UI.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(latestVersion: String)
    case available(AppRelease)
    case downloading(release: AppRelease, progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case readyToInstall(release: AppRelease, localFileURL: URL)
    case installerOpened(release: AppRelease, localFileURL: URL)
    case failed(title: String, detail: String, recoveryURL: URL?)
}

/// Manages periodic background update checks, background pre-fetching, cold-start prompts,
/// and guided/automatic installation from GitHub Releases.
@MainActor
@Observable
public final class UpdateManager {
    public static let repositorySlug = "CaptainCompileon/mac-charging-speed-widget"
    public static let releasesPageURL = URL(string: "https://github.com/\(repositorySlug)/releases/latest")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/\(repositorySlug)/releases/latest")!

    public private(set) var state: UpdateState = .idle
    public private(set) var availableRelease: AppRelease?
    public private(set) var lastCheckedDate: Date?
    public private(set) var isBackgroundPrefetching = false

    public var automaticUpdatesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticUpdatesEnabled, forKey: Keys.autoUpdatesEnabled)
            rescheduleBackgroundChecks()
            if automaticUpdatesEnabled, let release = availableRelease {
                Task { await prefetchInBackgroundIfNeeded(release) }
            }
        }
    }

    public var checkIntervalHours: Int {
        didSet {
            UserDefaults.standard.set(checkIntervalHours, forKey: Keys.checkIntervalHours)
            rescheduleBackgroundChecks()
        }
    }

    public var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.1.0"
    }

    public var currentBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "3"
    }

    public var hasUpdateAvailable: Bool {
        availableRelease != nil
    }

    private var backgroundTask: Task<Void, Never>?
    private var activeDownloadDelegate: ReleaseDownloadDelegate?
    private var activeDownloadSession: URLSession?
    private var cachedFileURLByVersion: [String: URL] = [:]

    private enum Keys {
        static let autoUpdatesEnabled = "updater.automaticUpdatesEnabled.v1"
        static let checkIntervalHours = "updater.checkIntervalHours.v1"
        static let lastCheckedTimestamp = "updater.lastCheckedTimestamp.v1"
    }

    public init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.autoUpdatesEnabled) == nil {
            defaults.set(true, forKey: Keys.autoUpdatesEnabled)
        }
        self.automaticUpdatesEnabled = defaults.bool(forKey: Keys.autoUpdatesEnabled)

        let savedHours = defaults.integer(forKey: Keys.checkIntervalHours)
        self.checkIntervalHours = savedHours > 0 ? savedHours : 6

        let savedTimestamp = defaults.double(forKey: Keys.lastCheckedTimestamp)
        if savedTimestamp > 0 {
            self.lastCheckedDate = Date(timeIntervalSince1970: savedTimestamp)
        }

        rescheduleBackgroundChecks()
    }

    // MARK: - Cold Start & Background Scheduling

    /// Always checks for updates on cold start and notifies the presenter so the user is prompted.
    public func checkOnColdStart() async {
        await checkForUpdates(isBackground: false)
    }

    /// Triggers an interactive update check initiated by the user.
    public func checkForUpdates(isBackground: Bool = false) async {
        if case .downloading = state { return }

        if !isBackground {
            state = .checking
        }

        do {
            let release = try await fetchLatestRelease()
            let now = Date()
            lastCheckedDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.lastCheckedTimestamp)

            if Self.isVersion(release.version, newerThan: currentVersion) {
                availableRelease = release

                if let cached = existingCachedFile(for: release) {
                    cachedFileURLByVersion[release.version] = cached
                    state = .readyToInstall(release: release, localFileURL: cached)
                } else {
                    state = .available(release)
                    if automaticUpdatesEnabled {
                        Task { await prefetchInBackgroundIfNeeded(release) }
                    }
                }
            } else {
                availableRelease = nil
                if !isBackground {
                    state = .upToDate(latestVersion: release.version)
                }
            }
        } catch {
            if !isBackground {
                let message = friendlyErrorMessage(for: error)
                state = .failed(
                    title: "Couldn’t Check for Updates",
                    detail: message,
                    recoveryURL: Self.releasesPageURL
                )
            }
        }
    }

    private func rescheduleBackgroundChecks() {
        backgroundTask?.cancel()
        backgroundTask = nil

        guard automaticUpdatesEnabled else { return }

        let intervalSeconds = max(1, checkIntervalHours) * 3600
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled, let self else { return }
                await self.checkForUpdates(isBackground: true)
            }
        }
    }

    // MARK: - Download & Install

    /// Downloads the update (or uses the background-prefetched package) and initiates installation.
    public func startUpdateNow() async {
        let release: AppRelease? = {
            switch state {
            case .available(let r), .readyToInstall(let r, _), .installerOpened(let r, _):
                return r
            default:
                return availableRelease
            }
        }()

        guard let release else { return }

        if let cached = existingCachedFile(for: release) {
            await completeInstall(release: release, localFileURL: cached)
            return
        }

        guard let downloadURL = release.preferredDownloadURL else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }

        state = .downloading(
            release: release,
            progress: 0,
            bytesWritten: 0,
            totalBytes: release.assetSizeBytes ?? 0
        )

        do {
            let localURL = try await downloadAsset(from: downloadURL, for: release, trackForegroundProgress: true)
            cachedFileURLByVersion[release.version] = localURL
            await completeInstall(release: release, localFileURL: localURL)
        } catch is CancellationError {
            state = .available(release)
        } catch {
            state = .failed(
                title: "Download Interrupted",
                detail: friendlyErrorMessage(for: error),
                recoveryURL: release.htmlURL
            )
        }
    }

    public func cancelActiveDownload() {
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadSession = nil
        activeDownloadDelegate = nil
        if let release = availableRelease {
            state = .available(release)
        } else {
            state = .idle
        }
    }

    public func openReleasesPage() {
        NSWorkspace.shared.open(availableRelease?.htmlURL ?? Self.releasesPageURL)
    }

    public func revealDownloadedInstaller() {
        if case .installerOpened(_, let fileURL) = state {
            NSWorkspace.shared.open(fileURL)
        } else if case .readyToInstall(_, let fileURL) = state {
            NSWorkspace.shared.open(fileURL)
        }
    }

    public func copyTerminalUpdateCommand() {
        let cmd = "curl -fsSL https://raw.githubusercontent.com/\(Self.repositorySlug)/main/scripts/install.sh | bash"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    // MARK: - Background Pre-Fetch

    private func prefetchInBackgroundIfNeeded(_ release: AppRelease) async {
        guard automaticUpdatesEnabled,
              !isBackgroundPrefetching,
              existingCachedFile(for: release) == nil,
              let downloadURL = release.preferredDownloadURL else {
            return
        }

        isBackgroundPrefetching = true
        defer { isBackgroundPrefetching = false }

        do {
            let fileURL = try await downloadAsset(from: downloadURL, for: release, trackForegroundProgress: false)
            cachedFileURLByVersion[release.version] = fileURL
            if case .available(let current) = state, current.version == release.version {
                state = .readyToInstall(release: release, localFileURL: fileURL)
            }
        } catch {
            // Silent in background; user can still trigger foreground download on demand.
        }
    }

    // MARK: - Installation Execution

    private func completeInstall(release: AppRelease, localFileURL: URL) async {
        // Open the downloaded DMG directly — works reliably both inside and outside App Sandbox.
        let opened = NSWorkspace.shared.open(localFileURL)
        if opened {
            state = .installerOpened(release: release, localFileURL: localFileURL)
        } else {
            state = .failed(
                title: "Couldn’t Open Installer",
                detail: "The update downloaded to \(localFileURL.lastPathComponent), but macOS could not open it automatically.",
                recoveryURL: release.htmlURL
            )
        }
    }

    // MARK: - Networking & Cache Helpers

    private func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseAPIURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacChargingSpeed/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdaterError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdaterError.httpStatus(http.statusCode)
        }

        let payload = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        let cleanVersion = Self.normalizeVersion(payload.tagName)

        let dmgAsset = payload.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        let zipAsset = payload.assets.first { $0.name.lowercased().hasSuffix(".zip") }
        let chosenAsset = dmgAsset ?? zipAsset

        let isoFormatter = ISO8601DateFormatter()
        let publishedDate = payload.publishedAt.flatMap { isoFormatter.date(from: $0) }

        let cleanedNotes = (payload.body ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AppRelease(
            tagName: payload.tagName,
            version: cleanVersion,
            title: payload.name?.isEmpty == false ? payload.name! : "MacChargingSpeed \(payload.tagName)",
            notes: cleanedNotes.isEmpty
                ? "Includes the latest Liquid Glass improvements, power telemetry fixes, and WidgetKit enhancements."
                : cleanedNotes,
            publishedAt: publishedDate,
            htmlURL: URL(string: payload.htmlURL) ?? Self.releasesPageURL,
            dmgDownloadURL: dmgAsset.flatMap { URL(string: $0.browserDownloadURL) },
            zipDownloadURL: zipAsset.flatMap { URL(string: $0.browserDownloadURL) },
            assetSizeBytes: chosenAsset?.size
        )
    }

    private func downloadAsset(
        from remoteURL: URL,
        for release: AppRelease,
        trackForegroundProgress: Bool
    ) async throws -> URL {
        let destURL = cacheDestinationURL(for: release, remoteURL: remoteURL)
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ReleaseDownloadDelegate(
                destinationURL: destURL,
                onProgress: { [weak self] written, expected in
                    guard trackForegroundProgress else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let total = expected > 0 ? expected : (release.assetSizeBytes ?? 0)
                        let fraction = total > 0 ? min(max(Double(written) / Double(total), 0), 1) : 0
                        self.state = .downloading(
                            release: release,
                            progress: fraction,
                            bytesWritten: written,
                            totalBytes: total
                        )
                    }
                },
                onFinish: { result in
                    continuation.resume(with: result)
                }
            )

            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = false
            config.timeoutIntervalForResource = 180
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

            if trackForegroundProgress {
                self.activeDownloadDelegate = delegate
                self.activeDownloadSession = session
            }

            var request = URLRequest(url: remoteURL)
            request.setValue("MacChargingSpeed/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    private func cacheDestinationURL(for release: AppRelease, remoteURL: URL) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let filename = remoteURL.lastPathComponent.isEmpty ? "MacChargingSpeed-\(release.version).dmg" : remoteURL.lastPathComponent
        return caches
            .appendingPathComponent("MacChargingSpeedUpdates", isDirectory: true)
            .appendingPathComponent(release.version, isDirectory: true)
            .appendingPathComponent(filename)
    }

    private func existingCachedFile(for release: AppRelease) -> URL? {
        if let remembered = cachedFileURLByVersion[release.version],
           FileManager.default.fileExists(atPath: remembered.path) {
            return remembered
        }
        guard let url = release.preferredDownloadURL else { return nil }
        let candidate = cacheDestinationURL(for: release, remoteURL: url)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let updaterError = error as? UpdaterError {
            switch updaterError {
            case .invalidResponse:
                return "GitHub returned an unexpected response. Try again in a moment or open the Releases page."
            case .httpStatus(403), .httpStatus(429):
                return "GitHub temporarily rate-limited update checks. Try again shortly or open Releases directly."
            case .httpStatus(let code):
                return "GitHub Releases returned status \(code). You can retry or download manually from GitHub."
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Your Mac appears to be offline. Reconnect to check for updates."
            case .timedOut:
                return "The connection to GitHub timed out. Try again when your connection stabilizes."
            default:
                break
            }
        }
        return "Check your internet connection and try again, or download directly from GitHub Releases."
    }

    // MARK: - Semantic Version Comparison

    public static func normalizeVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }

    public static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let leftParts = normalizeVersion(lhs).split(separator: "-").first?
            .split(separator: ".").compactMap { Int($0) } ?? []
        let rightParts = normalizeVersion(rhs).split(separator: "-").first?
            .split(separator: ".").compactMap { Int($0) } ?? []
        let count = max(leftParts.count, rightParts.count)
        for i in 0..<count {
            let l = i < leftParts.count ? leftParts[i] : 0
            let r = i < rightParts.count ? rightParts[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - Private Networking Types

private enum UpdaterError: Error {
    case invalidResponse
    case httpStatus(Int)
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let publishedAt: String?
    let assets: [AssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    struct AssetDTO: Decodable {
        let name: String
        let size: Int64
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }
}

private final class ReleaseDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let onFinish: @Sendable (Result<URL, Error>) -> Void
    private let lock = NSLock()
    private var completed = false

    init(
        destinationURL: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onFinish: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
            completeOnce(.success(destinationURL))
        } catch {
            completeOnce(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completeOnce(.failure(error))
            session.finishTasksAndInvalidate()
        }
    }

    private func completeOnce(_ result: Result<URL, Error>) {
        lock.lock()
        let shouldFire = !completed
        completed = true
        lock.unlock()
        if shouldFire {
            onFinish(result)
        }
    }
}
