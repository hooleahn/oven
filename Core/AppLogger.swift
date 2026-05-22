import Foundation

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
final class AppLogger: ObservableObject {

    static let shared = AppLogger()

    var entries: [LogEntry] = []

    private init() {}

    func log(_ message: String, level: LogEntry.Level = .info, source: String = "Oven") {
        let entry = LogEntry(timestamp: Date(), level: level, source: source, message: message)
        entries.append(entry)
        if entries.count > 1000 {
            entries.removeFirst(entries.count - 1000)
        }
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
