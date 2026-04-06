import Foundation

// MARK: - BuildMonitor
// Watches an active build for:
//   • Timeout — kills packer if it runs longer than the configured limit
//   • Heartbeat — warns if no log output for N minutes
//   • Disk space — aborts if free space drops too low during build

@MainActor
@Observable
final class BuildMonitor: ObservableObject {

    static let shared = BuildMonitor()
    private init() {}

    var isMonitoring = false
    var elapsedSeconds: Int = 0

    private var timeoutTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var diskTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var lastLogTime: Date = .now
    private var onTimeout: (() -> Void)?
    private var onHeartbeatWarning: ((Int) -> Void)?
    private var onLowDisk: ((Int64) -> Void)?

    // Settings keys (read from UserDefaults each build)
    static let timeoutMinutesKey        = "buildTimeoutMinutes"
    static let heartbeatMinutesKey      = "buildHeartbeatMinutes"
    static let minimumDiskBytesKey      = "buildMinimumDiskBytes"
    static let defaultTimeoutMinutes    = 180   // 3 hours
    static let defaultHeartbeatMinutes  = 10
    static let defaultMinimumDiskBytes: Int64 = 5 * 1_073_741_824  // 5 GB

    // MARK: - Lifecycle

    func start(
        onTimeout: @escaping () -> Void,
        onHeartbeatWarning: @escaping (Int) -> Void,
        onLowDisk: @escaping (Int64) -> Void
    ) {
        stop()
        isMonitoring = true
        elapsedSeconds = 0
        lastLogTime = .now
        self.onTimeout = onTimeout
        self.onHeartbeatWarning = onHeartbeatWarning
        self.onLowDisk = onLowDisk

        startElapsedTimer()
        startTimeoutWatcher()
        startHeartbeatWatcher()
        startDiskWatcher()
    }

    func stop() {
        timeoutTask?.cancel()
        heartbeatTask?.cancel()
        diskTask?.cancel()
        elapsedTask?.cancel()
        timeoutTask = nil; heartbeatTask = nil; diskTask = nil; elapsedTask = nil
        isMonitoring = false
    }

    /// Call this whenever a new log line arrives so the heartbeat resets.
    func ping() { lastLogTime = .now }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { elapsedSeconds += 1 }
            }
        }
    }

    // MARK: - Timeout watcher

    private func startTimeoutWatcher() {
        let minutes = UserDefaults.standard.integer(forKey: Self.timeoutMinutesKey)
        let limit   = (minutes > 0 ? minutes : Self.defaultTimeoutMinutes) * 60

        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(limit) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            AppLogger.shared.error(
                "Build timeout after \(limit / 60) minutes — killing packer",
                source: "BuildMonitor"
            )
            onTimeout?()
        }
    }

    // MARK: - Heartbeat watcher

    private func startHeartbeatWatcher() {
        let minutes = UserDefaults.standard.integer(forKey: Self.heartbeatMinutesKey)
        let limit   = (minutes > 0 ? minutes : Self.defaultHeartbeatMinutes) * 60

        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // check every minute
                guard !Task.isCancelled else { return }
                let silent = Int(-lastLogTime.timeIntervalSinceNow)
                if silent >= limit {
                    AppLogger.shared.warning(
                        "No build output for \(silent / 60) minutes — build may be stuck",
                        source: "BuildMonitor"
                    )
                    onHeartbeatWarning?(silent / 60)
                }
            }
        }
    }

    // MARK: - Disk space watcher

    private func startDiskWatcher() {
        let minBytes = UserDefaults.standard.object(forKey: Self.minimumDiskBytesKey) as? Int64
                       ?? Self.defaultMinimumDiskBytes

        diskTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000) // check every 2 minutes
                guard !Task.isCancelled else { return }
                let settings = AppSettings.load()
                for url in [settings.vmStorageRoot, settings.ipswStorageRoot] {
                    if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
                       let free  = attrs[.systemFreeSize] as? Int64,
                       free < minBytes {
                        let freeGB = Double(free) / 1_073_741_824
                        AppLogger.shared.error(
                            String(format: "Disk space critical: %.1f GB free in %@",
                                   freeGB, url.lastPathComponent),
                            source: "BuildMonitor"
                        )
                        onLowDisk?(free)
                        return // only fire once
                    }
                }
            }
        }
    }

    // MARK: - Formatted elapsed time

    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
