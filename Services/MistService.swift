import Foundation

// MARK: - Mist firmware info
// Field names match mist-cli's JSON export format exactly.

struct MistFirmwareInfo: Codable, Identifiable {
    var id: String { build }        // Identifiable uses build as ID
    let name: String                // e.g. "macOS Sequoia"
    let version: String             // e.g. "15.3.2"
    let build: String               // e.g. "24D81"
    let size: Int64                 // bytes
    let date: String                // e.g. "2025-03-12"
    let signed: Bool
    let compatible: Bool
    let url: String?                // download URL

    var displaySize: String {
        String(format: "%.1f GB", Double(size) / 1_073_741_824)
    }

    var fullLabel: String { "\(name) \(version) (\(build))" }

    // Flexible decoding — mist-cli has changed field names across versions
    private enum CodingKeys: String, CodingKey {
        case name, version, build, size, date, signed, compatible, url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name       = try c.decode(String.self, forKey: .name)
        version    = try c.decode(String.self, forKey: .version)
        build      = try c.decode(String.self, forKey: .build)
        date       = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        signed     = try c.decodeIfPresent(Bool.self, forKey: .signed) ?? false
        compatible = try c.decodeIfPresent(Bool.self, forKey: .compatible) ?? false
        url        = try c.decodeIfPresent(String.self, forKey: .url)

        // size can be Int64 or come as a nested object in some versions
        if let s = try? c.decode(Int64.self, forKey: .size) {
            size = s
        } else {
            size = 0
        }
    }
}

// MARK: - MistService

actor MistService {

    private let runner: ProcessRunner
    private let mistPath: String
    private let ipswRoot: URL

    // MARK: - Cache (mirrors IPSWService pattern)
    private static let cacheFile = AppSettings.defaultLocalStorageRoot
        .appendingPathComponent("mist-firmware-cache.json")
    private static let cacheTTL: TimeInterval = 86_400   // 24 hours

    private var cachedFirmwares: [MistFirmwareInfo]?
    private(set) var lastFetchDate: Date?

    var isCacheFresh: Bool {
        guard let date = lastFetchDate else { return false }
        return Date().timeIntervalSince(date) < MistService.cacheTTL
    }

    func invalidateCache() {
        cachedFirmwares = nil
        lastFetchDate = nil
        try? FileManager.default.removeItem(at: MistService.cacheFile)
    }

    init(runner: ProcessRunner, mistPath: String, ipswRoot: URL) {
        self.runner = runner
        self.mistPath = mistPath
        self.ipswRoot = ipswRoot
    }

    // MARK: - List firmware
    // mist-cli exports a JSON array via --export /path/file.json

    func listFirmware() async throws -> [MistFirmwareInfo] {
        // 1. In-memory cache
        if let cached = cachedFirmwares,
           let date = lastFetchDate,
           Date().timeIntervalSince(date) < MistService.cacheTTL {
            return cached
        }
        // 2. Disk cache
        if let (diskFirmwares, diskDate) = loadDiskCache(),
           Date().timeIntervalSince(diskDate) < MistService.cacheTTL {
            cachedFirmwares = diskFirmwares
            lastFetchDate = diskDate
            return diskFirmwares
        }
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("oven-mist-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        // Run mist list firmware --export <file> --no-ansi
        try await runner.run(
            mistPath,
            arguments: ["list", "firmware", "--export", tmpFile.path, "--no-ansi"]
        )

        guard FileManager.default.fileExists(atPath: tmpFile.path) else {
            throw MistError.exportFileMissing
        }
        let data = try Data(contentsOf: tmpFile)
        guard !data.isEmpty else { throw MistError.emptyExport }

        // tart requires macOS 12 Monterey or later — exclude Big Sur (11.x) and older.
        // Filter to signed=true only — mist returns both signed and unsigned versions
        // for each release. Using `signed` (not `compatible`) preserves releases that
        // are signed but not compatible with this specific machine model.
        func supported(_ fw: MistFirmwareInfo) -> Bool {
            guard let major = Int(fw.version.split(separator: ".").first ?? "") else { return true }
            return major >= 12 && fw.signed
        }

        // Attempt direct array decode first, then wrapped object
        let results: [MistFirmwareInfo]
        if let firmwares = try? JSONDecoder().decode([MistFirmwareInfo].self, from: data) {
            results = firmwares.filter(supported)
        } else {
            struct Wrapped: Decodable { let firmwares: [MistFirmwareInfo] }
            if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
                results = wrapped.firmwares.filter(supported)
            } else {
                let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
                throw MistError.decodeFailed(preview)
            }
        }
        // Write cache
        cachedFirmwares = results
        lastFetchDate = Date()
        saveDiskCache(results)
        return results
    }

    // MARK: - Disk cache helpers

    private func loadDiskCache() -> ([MistFirmwareInfo], Date)? {
        let url = MistService.cacheFile
        guard let data = try? Data(contentsOf: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        let envelope = try? JSONDecoder().decode([MistFirmwareInfo].self, from: data)
        return envelope.map { ($0, modified) }
    }

    private func saveDiskCache(_ firmwares: [MistFirmwareInfo]) {
        guard let data = try? JSONEncoder().encode(firmwares) else { return }
        try? FileManager.default.createDirectory(
            at: MistService.cacheFile.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: MistService.cacheFile, options: Data.WritingOptions.atomic)
    }

    // MARK: - Download firmware

    /// Download firmware shown in InstallerView (build known from list result).
    func downloadFirmware(version: String, build: String) async -> AsyncStream<ProcessEvent> {
        let filename = standardFilename(osVersion: version)
        return await runner.stream(
            mistPath,
            arguments: [
                "download", "firmware", version,
                "--firmware-name", filename,
                "--output-directory", ipswRoot.path,
                "--no-ansi",
            ]
        )
    }

    /// Download firmware by version string, using a predictable output filename.
    /// Returns the expected file URL so the caller can use it directly after download.
    func downloadFirmwareByVersion(_ version: String) async -> (stream: AsyncStream<ProcessEvent>, expectedURL: URL) {
        let filename = standardFilename(osVersion: version)
        let expectedURL = ipswRoot.appendingPathComponent(filename)
        let stream = await runner.stream(
            mistPath,
            arguments: [
                "download", "firmware", version,
                "--firmware-name", filename,
                "--output-directory", ipswRoot.path,
                "--no-ansi",
            ]
        )
        return (stream, expectedURL)
    }

    /// Standard IPSW filename: "macOS <version>.ipsw" (matches Installers view display)
    private func standardFilename(osVersion: String) -> String {
        var majorVersion: Int {
            Int(osVersion.split(separator: ".").first ?? "") ?? 0
        }

        /// Friendly OS name, e.g. "macOS Sequoia 15.6.1"
        var displayName: String {
            let name: String
            switch majorVersion {
            case 26: name = "macOS Tahoe"
            case 15: name = "macOS Sequoia"
            case 14: name = "macOS Sonoma"
            case 13: name = "macOS Ventura"
            case 12: name = "macOS Monterey"
            default: name = "macOS"
            }
            return "\(name) \(osVersion)"
        }

        /// Suggested local filename
        var suggestedFilename: String {
            "\(displayName).ipsw"
        }
        return suggestedFilename
    }

    // MARK: - Local IPSW discovery

    func localIPSWs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: ipswRoot.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: ipswRoot, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "ipsw" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

// MARK: - Errors

enum MistError: LocalizedError {
    case exportFileMissing
    case emptyExport
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportFileMissing:
            return "mist-cli ran but did not create an export file. Check that mist-cli is installed correctly."
        case .emptyExport:
            return "mist-cli export was empty. Try running 'mist list firmware' in Terminal to check connectivity."
        case .decodeFailed(let preview):
            return "mist-cli JSON could not be decoded. Raw output: \(preview)"
        }
    }
}
