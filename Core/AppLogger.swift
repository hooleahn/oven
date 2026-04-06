import Foundation

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
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > 1000 {
                self.entries.removeFirst(self.entries.count - 1000)
            }
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
    }

    func clear() { entries.removeAll() }
}
