import Foundation

// MARK: - StreamConsumer
//
// Reduces the repeated `for await event in stream { switch event { ... } }`
// pattern to a single call. Three pre-built consumers cover all Oven use cases.

// MARK: - Result type

struct StreamResult {
    var stdoutLines: [String] = []
    var stderrLines: [String] = []
    var exitCode: Int32 = 0

    var allLines: [String] { stdoutLines + stderrLines }
    var succeeded: Bool { exitCode == 0 }

    /// All output joined — useful for error message extraction.
    var combinedOutput: String { allLines.joined(separator: "\n") }
}

// MARK: - Consumer

/// Consume a `ProcessEvent` stream with per-event callbacks.
///
/// Usage:
/// ```swift
/// let result = await StreamConsumer.consume(stream) { line in
///     myLog.append(line)
/// } onStderr: { line in
///     // optional — defaults to same handler as onStdout
/// }
/// ```
enum StreamConsumer {

    // MARK: - Generic consume

    /// Consume a stream, calling `onStdout` for each stdout line,
    /// `onStderr` for each stderr line (defaults to `onStdout`),
    /// and returning a `StreamResult` when done.
    @discardableResult
    static func consume(
        _ stream: AsyncStream<ProcessEvent>,
        onStdout: ((String) -> Void)? = nil,
        onStderr: ((String) -> Void)? = nil
    ) async -> StreamResult {
        var result = StreamResult()
        for await event in stream {
            switch event {
            case .stdout(let line):
                result.stdoutLines.append(line)
                (onStdout ?? onStderr)?(line)
            case .stderr(let line):
                result.stderrLines.append(line)
                (onStderr ?? onStdout)?(line)
            case .exit(let code):
                result.exitCode = code
            }
        }
        return result
    }

    // MARK: - Pre-built consumers

    /// Log all lines to AppLogger and return the result.
    /// Used by: VM start, registry pull/push.
    @discardableResult
    static func logged(
        _ stream: AsyncStream<ProcessEvent>,
        source: String,
        onLine: ((String) -> Void)? = nil
    ) async -> StreamResult {
        await consume(stream) { line in
            Task { await AppLogger.shared.log(line, source: source) }
            onLine?(line)
        } onStderr: { line in
            Task { await AppLogger.shared.error(line, source: source) }
            onLine?(line)
        }
    }

    /// Append lines to a build log array + AppLogger + BuildMonitor heartbeat.
    /// Used by: BaseVMStore build, mist download.
    @discardableResult
    static func buildLog(
        _ stream: AsyncStream<ProcessEvent>,
        source: String,
        appendLine: @escaping @MainActor (String) -> Void
    ) async -> StreamResult {
        await consume(stream) { line in
            Task { @MainActor in appendLine(line) }
            Task { await AppLogger.shared.log(line, source: source) }
            Task { @MainActor in BuildMonitor.shared.ping() }
        } onStderr: { line in
            let isError = line.contains("[ERROR]") || line.contains("Error:") || line.hasPrefix("error:")
            let display = isError ? "[err] \(line)" : line
            Task { @MainActor in appendLine(display) }
            Task {
                if isError {
                    await AppLogger.shared.error(line, source: source)
                } else {
                    await AppLogger.shared.log(line, source: source)
                }
            }
            Task { @MainActor in BuildMonitor.shared.ping() }
        }
    }

    /// Collect all output silently and return the result.
    /// Used by: operations where only the exit code matters.
    @discardableResult
    static func silent(
        _ stream: AsyncStream<ProcessEvent>
    ) async -> StreamResult {
        await consume(stream)
    }
}
