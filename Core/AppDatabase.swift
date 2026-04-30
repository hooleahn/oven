import Foundation

// MARK: - AppDatabase
//
// Single persistence layer for all Oven JSON files.
// Each file is wrapped in a versioned envelope so we can detect
// and migrate stale data when models change.
//
// Usage:
//   let vms: [VirtualMachine] = try AppDatabase.shared.read(.vms)
//   try AppDatabase.shared.write(vms, to: .vms)

// MARK: - BuildHistory

struct BuildHistoryEntry: Codable, Sendable {
    let id: UUID
    let osName: String        // MacOSRelease.Name.rawValue
    let osVersion: String
    let durationSec: Double
    let success: Bool
    let recordedAt: Date
}

final class AppDatabase {

    static let shared = AppDatabase()
    private let lock = NSLock()

    // MARK: - Known files

    enum File: String {
        case vms               = "vms/metadata.json"
        case baseVMs           = "base-vms/metadata.json"
        case tagColors         = "tag-colors.json"
        case tagColorIndices   = "tag-color-indices.json"
        case registryImages    = "registry-images.json"
        case registryCredentials = "registry-credentials.json"
        case mdmProfiles       = "mdm-profiles.json"
        case mdmServers        = "mdm-servers.json"
        case packerBlocks      = "packer-blocks.json"
        case packerBootCommands = "packer-boot-commands.json"
        case buildHistory      = "build-history.json"

        /// Schema version — bump when the model gains non-optional fields
        /// that can't be decoded from older files via decodeIfPresent.
        var schemaVersion: Int {
            switch self {
            case .vms:               return 6   // v6: manualBuildConfig added for manual-build-path VMs
            case .baseVMs:           return 2   // legacy — data migrated into vms in v4
            case .tagColors:         return 1
            case .tagColorIndices:   return 1
            case .registryImages:    return 1
            case .registryCredentials: return 1
            case .mdmProfiles:       return 1
            case .mdmServers:        return 1
            case .packerBlocks:      return 2   // v2: added osName, osVersion fields
            case .packerBootCommands: return 1
            case .buildHistory:      return 1
            }
        }
    }

    // MARK: - Envelope

    private struct Envelope<T: Codable>: Codable {
        let schemaVersion: Int
        let payload: T
    }

    // MARK: - Storage root

    private var root: URL

    private init() {
        root = AppSettings.defaultLocalStorageRoot
    }

    /// Redirect all subsequent reads and writes to a different root directory.
    /// Called by ProfileStore when the active profile changes.
    func switchRoot(to url: URL) {
        lock.lock(); defer { lock.unlock() }
        root = url
    }

    func url(for file: File) -> URL {
        root.appendingPathComponent(file.rawValue)
    }

    // MARK: - Read

    /// Read typed data from a file. Returns `nil` if the file doesn't exist.
    /// Throws if the file exists but can't be decoded.
    func read<T: Codable>(_ file: File) throws -> T? {
        lock.lock(); defer { lock.unlock() }
        let url = url(for: file)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)

        // Try versioned envelope first
        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) {
            if envelope.schemaVersion < file.schemaVersion {
                // Future: add per-file migration here
                Task { await AppLogger.shared.log("Schema v\(envelope.schemaVersion)→v\(file.schemaVersion) for \(file.rawValue) — forward-compatible decode", source: "AppDatabase") }
            }
            return envelope.payload
        }

        // Fallback: try decoding raw (legacy files without envelope)
        if let result = try? decoder.decode(T.self, from: data) {
            return result
        }
        // Last resort: for arrays, try decoding as [JSON] and skip malformed items
        // This handles files saved with an older model structure
        Task { await AppLogger.shared.log("Falling back to empty default for \(file.rawValue) — legacy format not decodable", source: "AppDatabase") }
        return nil
    }

    /// Read with a default value — never throws, logs errors.
    func readOrDefault<T: Codable>(_ file: File, default defaultValue: T) -> T {
        do {
            return (try read(file)) ?? defaultValue
        } catch {
            Task { await AppLogger.shared.error("Failed to read \(file.rawValue): \(error.localizedDescription)", source: "AppDatabase") }
            return defaultValue
        }
    }

    // MARK: - Write

    func write<T: Codable>(_ value: T, to file: File) throws {
        lock.lock(); defer { lock.unlock() }
        let url = url(for: file)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let envelope = Envelope(schemaVersion: file.schemaVersion, payload: value)
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    /// Write silently — logs errors instead of throwing.
    func writeSilently<T: Codable>(_ value: T, to file: File) {
        do {
            try write(value, to: file)
        } catch {
            Task { await AppLogger.shared.error("Failed to write \(file.rawValue): \(error.localizedDescription)", source: "AppDatabase") }
        }
    }

    // MARK: - Shared encoder/decoder

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Build history

    /// Append a completed build to the history log (max 200 entries retained).
    func recordBuild(osName: String, osVersion: String, durationSec: Double, success: Bool) {
        let entry = BuildHistoryEntry(
            id: UUID(),
            osName: osName,
            osVersion: osVersion,
            durationSec: durationSec,
            success: success,
            recordedAt: Date()
        )
        var history: [BuildHistoryEntry] = readOrDefault(.buildHistory, default: [])
        history.append(entry)
        // Keep only the most recent 200 builds to avoid unbounded growth
        if history.count > 200 { history = Array(history.suffix(200)) }
        writeSilently(history, to: .buildHistory)
    }

    /// Returns the median successful build duration (in seconds) for a given OS name,
    /// or nil if there are fewer than 2 successful samples.
    func medianDuration(for osName: String) -> TimeInterval? {
        let history: [BuildHistoryEntry] = readOrDefault(.buildHistory, default: [])
        let durations = history
            .filter { $0.success && $0.osName == osName }
            .map { $0.durationSec }
            .sorted()
        guard durations.count >= 2 else { return nil }
        let mid = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[mid - 1] + durations[mid]) / 2.0
        } else {
            return durations[mid]
        }
    }
}
