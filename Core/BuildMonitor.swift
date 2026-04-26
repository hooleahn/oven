import Foundation

// MARK: - BuildPhase

enum BuildPhase: Int, CaseIterable, Sendable {
    case prepare   = 0
    case download  = 1
    case install   = 2
    case provision = 3
    case finalize  = 4

    var label: String {
        switch self {
        case .prepare:   return "Prepare"
        case .download:  return "Download"
        case .install:   return "Install"
        case .provision: return "Provision"
        case .finalize:  return "Finalize"
        }
    }

    /// Approximate progress fraction at the midpoint of this phase,
    /// used as a fallback when no median build time is available.
    var midProgress: Double {
        switch self {
        case .prepare:   return 0.05
        case .download:  return 0.25
        case .install:   return 0.50
        case .provision: return 0.75
        case .finalize:  return 0.95
        }
    }
}

// MARK: - BuildMonitor
// Watches an active build for:
//   • Timeout — kills packer if it runs longer than the configured limit
//   • Heartbeat — warns if no log output for N minutes
//   • Disk space — aborts if free space drops too low during build
//   • Phase — advances through BuildPhase cases based on log patterns
//   • Progress — determinate 0.0–1.0 estimate using elapsed time + ETA

@MainActor
@Observable
final class BuildMonitor: ObservableObject {

    static let shared = BuildMonitor()
    private init() {}

    var isMonitoring = false
    var elapsedSeconds: Int = 0

    // MARK: - Phase & progress tracking

    var phase: BuildPhase = .prepare
    var progress: Double = 0.0

    /// osName used for ETA lookup (set when the build starts)
    private var currentOSName: String = ""
    private var buildStartDate: Date = .now

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
        onLowDisk: @escaping (Int64) -> Void,
        osName: String = ""
    ) {
        stop()
        isMonitoring = true
        elapsedSeconds = 0
        phase = .prepare
        progress = 0.0
        currentOSName = osName
        buildStartDate = .now
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

    /// Process a build log line — advance phase and update progress estimate.
    func processLogLine(_ line: String) {
        ping()
        advancePhase(for: line)
        updateProgress()
    }

    // MARK: - Phase advancement

    private func advancePhase(for line: String) {
        let l = line.lowercased()

        let newPhase: BuildPhase?
        if l.contains("downloading ipsw") || l.contains("restore image") || l.contains("% ") && phase == .prepare {
            newPhase = .download
        } else if l.contains("creating vm") || l.contains("tart create") || l.contains("==> tart:") {
            newPhase = .install
        } else if l.contains("provisioner: shell") || l.contains("ansible") || l.contains("==> tart: provisioner") {
            newPhase = .provision
        } else if l.contains("image successfully generated") || l.contains("build complete") || l.contains("build successful") {
            newPhase = .finalize
        } else {
            newPhase = nil
        }

        if let np = newPhase, np.rawValue > phase.rawValue {
            phase = np
            if np == .finalize {
                progress = 1.0
            }
        }
    }

    // MARK: - Progress estimation

    private func updateProgress() {
        guard phase != .finalize else { progress = 1.0; return }
        let elapsed = -buildStartDate.timeIntervalSinceNow

        // Try to use a median build duration for this OS
        if let median = AppDatabase.shared.medianDuration(for: currentOSName), median > 0 {
            progress = min(elapsed / median, 0.99)
        } else {
            // Fallback: interpolate within the current phase band
            // Each phase occupies an equal slice; use elapsed vs phase midpoint
            let mid = phase.midProgress
            let nextMid = phase.rawValue < BuildPhase.allCases.count - 1
                ? BuildPhase(rawValue: phase.rawValue + 1)!.midProgress
                : 0.99
            // Assume each phase takes roughly equal time at ~30 min total
            let estimatedTotal: Double = 30 * 60
            let fraction = min(elapsed / estimatedTotal, 0.99)
            progress = max(min(fraction, nextMid - 0.01), mid)
        }
    }

    // MARK: - Record completed build

    /// Call this when a build finishes to persist the duration for future ETA calculations.
    func recordCompletion(osName: String, osVersion: String, success: Bool) {
        let duration = -buildStartDate.timeIntervalSinceNow
        AppDatabase.shared.recordBuild(
            osName: osName,
            osVersion: osVersion,
            durationSec: max(duration, 1),
            success: success
        )
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled {
                    elapsedSeconds += 1
                    // Refresh progress estimate every second so the bar moves smoothly
                    if phase != .finalize { updateProgress() }
                }
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

    /// Human-readable remaining time estimate, or nil if not enough data.
    var remainingFormatted: String? {
        guard progress > 0.01 && progress < 1.0 else { return nil }
        let elapsed = -buildStartDate.timeIntervalSinceNow
        let estimated = elapsed / progress
        let remaining = max(estimated - elapsed, 0)
        let totalSeconds = Int(remaining)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "~%d:%02d:%02d", h, m, s) }
        return String(format: "~%d:%02d", m, s)
    }
}
