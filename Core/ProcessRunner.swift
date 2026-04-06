import Foundation

// MARK: - Output event

/// A single event emitted by a running process.
enum ProcessEvent: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

// MARK: - Errors

enum ProcessError: LocalizedError {
    case binaryNotFound(String)
    case nonZeroExit(Int32, String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "Binary not found at path: \(path)"
        case .nonZeroExit(let code, let stderr):
            return "Process exited with code \(code): \(stderr)"
        case .launchFailed(let reason):
            return "Failed to launch process: \(reason)"
        }
    }
}

// MARK: - ProcessRunner

/// Wraps Foundation.Process with async/await and AsyncStream support.
/// All services (TartService, PackerService, MistService, etc.) go through here.
actor ProcessRunner {

    // MARK: - Streaming run (for long-running processes like builds)

    /// Run a process and stream its output line by line as ProcessEvents.
    /// Use this for Packer builds, mist-cli downloads, and anything with live log output.
    func stream(
        _ executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) -> AsyncStream<ProcessEvent> {
        // Log the full command in debug mode so Activity Log shows exactly what ran
        let cmdString = ([executablePath] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
        Task { await AppLogger.shared.log("$ \(cmdString)", source: "ProcessRunner") }

        return AsyncStream { continuation in
            Task {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                // Redirect stdin to /dev/null so interactive prompts never block
                process.standardInput = FileHandle.nullDevice

                if let env = environment {
                    var merged = ProcessInfo.processInfo.environment
                    env.forEach { merged[$0] = $1 }
                    process.environment = merged
                }

                if let cwd = workingDirectory {
                    process.currentDirectoryURL = cwd
                }

                // Line buffers wrapped in a class so closures capture a reference,
                // not an inout var — avoids Swift 6 concurrency warnings.
                // Access is serialised by NSLock.
                final class Bufs { var out = ""; var err = "" }
                let bufs = Bufs()
                let lock = NSLock()

                // Splits incoming text on CR/LF, yields complete lines, keeps partial tail.
                // Must be called with `lock` held.
                @Sendable func yieldLines(_ text: String, buf: inout String,
                                make: (String) -> ProcessEvent) {
                    let combined = buf + text
                    var parts = combined.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
                    buf = parts.removeLast()
                    for line in parts where !line.isEmpty {
                        continuation.yield(make(line))
                    }
                }

                let stdoutHandle = stdoutPipe.fileHandleForReading
                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    lock.lock(); defer { lock.unlock() }
                    yieldLines(text, buf: &bufs.out) { .stdout($0) }
                }

                let stderrHandle = stderrPipe.fileHandleForReading
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    lock.lock(); defer { lock.unlock() }
                    yieldLines(text, buf: &bufs.err) { .stderr($0) }
                }

                process.terminationHandler = { p in
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    lock.lock(); defer { lock.unlock() }
                    let remainingOut = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    yieldLines(remainingOut + "\n", buf: &bufs.out) { .stdout($0) }
                    let remainingErr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    yieldLines(remainingErr + "\n", buf: &bufs.err) { .stderr($0) }
                    continuation.yield(.exit(p.terminationStatus))
                    continuation.finish()
                }

                do {
                    try process.run()
                } catch {
                    continuation.yield(.stderr("Launch failed: \(error.localizedDescription)"))
                    continuation.yield(.exit(-1))
                    continuation.finish()
                }

                // Support cancellation — terminate the process if the task is cancelled
                continuation.onTermination = { _ in
                    if process.isRunning { process.terminate() }
                }
            }
        }
    }

    // MARK: - Fire-and-collect run (for quick commands)

    /// Run a process to completion and return (stdout, stderr, exitCode).
    /// Use this for tart list, tart ip, jq queries, etc.
    @discardableResult
    func run(
        _ executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) async throws -> (stdout: String, stderr: String) {
        var stdoutLines: [String] = []
        var stderrLines: [String] = []
        var exitCode: Int32 = 0

        for await event in stream(executablePath, arguments: arguments, environment: environment, workingDirectory: workingDirectory) {
            switch event {
            case .stdout(let line): stdoutLines.append(line)
            case .stderr(let line): stderrLines.append(line)
            case .exit(let code):  exitCode = code
            }
        }

        let stdout = stdoutLines.joined(separator: "\n")
        let stderr = stderrLines.joined(separator: "\n")

        guard exitCode == 0 else {
            throw ProcessError.nonZeroExit(exitCode, stderr)
        }

        return (stdout, stderr)
    }

    // MARK: - JSON run (convenience for commands that output JSON)

    /// Run a process and decode its stdout as JSON.
    func runJSON<T: Decodable>(
        _ executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> T {
        let (stdout, _) = try await run(executablePath, arguments: arguments, environment: environment)
        guard let data = stdout.data(using: .utf8) else {
            throw ProcessError.launchFailed("Could not encode stdout as UTF-8")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
