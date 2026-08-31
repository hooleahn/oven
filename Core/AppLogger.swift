import Foundation
import os

// MARK: - Notification names

extension Notification.Name {
    /// Posted by ToastCenter deep-links to navigate to the Activity Log.
    /// `object` is the source string (String?) to pre-filter on.
    static let navigateToLog = Notification.Name("oven.navigateToLog")
}

// MARK: - Log entry

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: Level
    let source: String      // e.g. "TartService", "PackerService"
    let message: String

    enum Level: String {
        case debug   = "DEBUG"
        case info    = "INFO"
        case success = "OK"
        case warning = "WARN"
        case error   = "ERROR"
    }

    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - AppLogger

@MainActor
@Observable
final class AppLogger {

    static let shared = AppLogger()

    var entries: [LogEntry] = []

    /// One os.Logger per source (e.g. "TartService", "ProcessRunner"), so Console.app
    /// can filter/group by category the same way the Activity Log groups by source.
    private var osLoggers: [String: Logger] = [:]

    private init() {}

    private func osLogger(for source: String) -> Logger {
        if let existing = osLoggers[source] { return existing }
        let subsystem = Bundle.main.bundleIdentifier ?? "com.hooleahn.oven"
        let logger = Logger(subsystem: subsystem, category: source)
        osLoggers[source] = logger
        return logger
    }

    /// Unified-logging type is the closest analog for each Activity Log level.
    /// `.success` and `.info` both surface as `.info` in Console; `.warning` maps to
    /// `.default` (there's no dedicated OSLogType for "warning").
    private func osLogType(for level: LogEntry.Level) -> OSLogType {
        switch level {
        case .debug:   return .debug
        case .info:    return .info
        case .success: return .info
        case .warning: return .default
        case .error:   return .error
        }
    }

    func log(_ message: String, level: LogEntry.Level = .info, source: String = "Oven") {
        let entry = LogEntry(timestamp: Date.now, level: level, source: source, message: message)
        entries.append(entry)
        if entries.count > 1000 {
            entries.removeFirst(entries.count - 1000)
        }
        // Messages are diagnostic by design and already scrub secrets at the call
        // site (e.g. "Password: REDACTED"), so mark them public — otherwise unified
        // logging redacts interpolated values as "<private>" in Console.app.
        osLogger(for: source).log(level: osLogType(for: level), "\(message, privacy: .public)")
    }

    /// Logs at debug level, but only when the user has enabled "Debug Mode" in
    /// Preferences — mirrors the gate every call site used to duplicate individually
    /// via `UserDefaults.standard.bool(forKey: "debugModeEnabled")`.
    func debug(_ message: String, source: String = "Oven") {
        guard UserDefaults.standard.bool(forKey: "debugModeEnabled") else { return }
        log(message, level: .debug, source: source)
    }

    func success(_ message: String, source: String = "Oven") {
        log(message, level: .success, source: source)
    }

    func warning(_ message: String, source: String = "Oven") {
        log(message, level: .warning, source: source)
    }

    func error(_ message: String, source: String = "Oven") {
        log(message, level: .error, source: source)
        // Mirror to the global toast banner so errors surface immediately,
        // regardless of which sidebar tab the user is viewing.
        // The deep-link navigates to the Activity Log filtered to this source.
        ToastCenter.shared.push(
            message,
            severity: .error,
            source: source,
            deepLink: {
                // Routing is handled in ContentView via a notification so
                // ToastCenter stays decoupled from the NavigationSplitView state.
                NotificationCenter.default.post(
                    name: .navigateToLog,
                    object: source
                )
            }
        )
    }

    func clear() { entries.removeAll() }
}
