import Foundation

// MARK: - IPSW.me API response types

struct IPSWFirmware: Codable, Identifiable, Sendable, Equatable {
    let identifier: String
    let version: String
    let buildid: String
    let sha256sum: String
    let filesize: Int64
    let url: String
    let releasedate: String
    let signed: Bool

    var id: String { buildid }

    /// Human-friendly file size, e.g. "15.7 GB"
    var formattedSize: String {
        let gb = Double(filesize) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }

    /// macOS major version integer, e.g. 15 for "15.6.1"
    var majorVersion: Int {
        Int(version.split(separator: ".").first ?? "") ?? 0
    }

    /// Friendly OS name, e.g. "macOS Sequoia 15.6.1"
    var displayName: String {
        let name: String
        switch majorVersion {
        case 27: name = "macOS Golden Gate"
        case 26: name = "macOS Tahoe"
        case 15: name = "macOS Sequoia"
        case 14: name = "macOS Sonoma"
        case 13: name = "macOS Ventura"
        case 12: name = "macOS Monterey"
        default: name = "macOS"
        }
        return "\(name) \(version)"
    }

    /// Suggested local filename
    var suggestedFilename: String {
        "\(displayName).ipsw"
    }

    enum CodingKeys: String, CodingKey {
        case identifier, version, buildid, sha256sum, filesize, url
        case releasedate, signed
    }
}

private struct IPSWDeviceResponse: Decodable {
    let firmwares: [IPSWFirmware]
}

// MARK: - IPSWService

/// Fetches available macOS firmware for Apple Virtual Machine hardware
/// (VirtualMac2,1) from the ipsw.me API. No external tools required.
actor IPSWService {

    static let shared = IPSWService()

    private let deviceIdentifier = "VirtualMac2,1"
    private static let cacheFile = AppSettings.defaultLocalStorageRoot
        .appendingPathComponent("ipsw-firmware-cache.json")
    private static let cacheTTL: TimeInterval = 86_400   // 24 hours

    private var cachedFirmwares: [IPSWFirmware]?
    private(set) var lastFetchDate: Date?

    // MARK: - Firmware list

    /// Returns firmwares compatible with tart VMs, sorted newest-first.
    /// Results are cached for the session; call invalidateCache() to force refresh.
    func listFirmware() async throws -> [IPSWFirmware] {
        // 1. In-memory cache (fastest)
        if let cached = cachedFirmwares,
           let date = lastFetchDate,
           Date().timeIntervalSince(date) < IPSWService.cacheTTL {
            return cached
        }
        // 2. Disk cache — survives app restarts
        if let (diskFirmwares, diskDate) = loadDiskCache(),
           Date().timeIntervalSince(diskDate) < IPSWService.cacheTTL {
            cachedFirmwares = diskFirmwares
            lastFetchDate = diskDate
            return diskFirmwares
        }

        let urlString = "https://api.ipsw.me/v4/device/\(deviceIdentifier)?type=ipsw"
        guard let url = URL(string: urlString) else {
            throw IPSWError.invalidURL
        }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy,
                                  timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw IPSWError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode(IPSWDeviceResponse.self, from: data)

        // Filter: macOS 12+ only (tart minimum), sorted newest-first
        let firmwares = decoded.firmwares
            .filter { $0.majorVersion >= 12 }
            .sorted {
                // Sort by version components numerically
                let a = $0.version.split(separator: ".").compactMap { Int($0) }
                let b = $1.version.split(separator: ".").compactMap { Int($0) }
                for (x, y) in zip(a, b) {
                    if x != y { return x > y }
                }
                return a.count > b.count
            }

        cachedFirmwares = firmwares
        lastFetchDate = Date()
        saveDiskCache(firmwares)
        return firmwares
    }

    /// Force-expire the cache. Call when user taps Refresh.
    func invalidateCache() {
        cachedFirmwares = nil
        lastFetchDate = nil
        try? FileManager.default.removeItem(at: IPSWService.cacheFile)
    }

    /// Returns true if cached data is still fresh (< 24h old).
    var isCacheFresh: Bool {
        if let date = lastFetchDate, Date().timeIntervalSince(date) < IPSWService.cacheTTL { return true }
        if let (_, diskDate) = loadDiskCache(),
           Date().timeIntervalSince(diskDate) < IPSWService.cacheTTL { return true }
        return false
    }

    // MARK: - Disk persistence

    private func saveDiskCache(_ firmwares: [IPSWFirmware]) {
        let payload = CachePayload(date: Date(), firmwares: firmwares)
        if let data = try? JSONEncoder().encode(payload) {
            try? FileManager.default.createDirectory(
                at: AppSettings.defaultLocalStorageRoot, withIntermediateDirectories: true)
            try? data.write(to: IPSWService.cacheFile, options: .atomic)
        }
    }

    private func loadDiskCache() -> ([IPSWFirmware], Date)? {
        guard let data = try? Data(contentsOf: IPSWService.cacheFile),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return nil }
        return (payload.firmwares, payload.date)
    }

    private struct CachePayload: Codable {
        let date: Date
        let firmwares: [IPSWFirmware]
    }

    // MARK: - Download

    /// Download an IPSW to the given directory, yielding progress events.
    func download(_ firmware: IPSWFirmware,
                  to directory: URL) -> AsyncStream<IPSWDownloadEvent> {
        AsyncStream { continuation in
            let dest = directory.appendingPathComponent(firmware.suggestedFilename)
            print("Downloading \(firmware.url) to \(dest.path)")
            // Already on disk — return immediately
            if FileManager.default.fileExists(atPath: dest.path) {
                continuation.yield(.progress(1.0, firmware.filesize, firmware.filesize))
                continuation.yield(.completed(dest))
                continuation.finish()
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
            } catch {
                continuation.yield(.failed(error))
                continuation.finish()
                return
            }

            guard let url = URL(string: firmware.url) else {
                continuation.yield(.failed(IPSWError.invalidURL))
                continuation.finish()
                return
            }

            let delegate = DownloadDelegate(continuation: continuation,
                                            totalBytes: firmware.filesize,
                                            destination: dest)
            let session = URLSession(configuration: .default, delegate: delegate,
                                     delegateQueue: nil)
            let task = session.downloadTask(with: URLRequest(url: url))
            task.resume()

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Download events

enum IPSWDownloadEvent: Sendable {
    case progress(Double, Int64, Int64)   // fraction, bytesWritten, totalBytes
    case completed(URL)
    case failed(Error)
}

// MARK: - URLSession download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let continuation: AsyncStream<IPSWDownloadEvent>.Continuation
    let totalBytes: Int64
    let destination: URL

    init(continuation: AsyncStream<IPSWDownloadEvent>.Continuation,
         totalBytes: Int64, destination: URL) {
        self.continuation = continuation
        self.totalBytes = totalBytes
        self.destination = destination
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalBytes
        let fraction = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        continuation.yield(.progress(fraction, totalBytesWritten, total))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let dest = destination
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                print("Removing previous IPSW: \(dest.path)")
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            print("Downloaded IPSW: \(dest.path)")
            continuation.yield(.completed(dest))
        } catch {
            print("Failed to move downloaded IPSW: \(error)")
            continuation.yield(.failed(error))
        }
        print("Downloaded IPSW: \(dest.path)")
        continuation.finish()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            print("Download failed: \(error)")
            continuation.yield(.failed(error))
            continuation.finish()
        }
    }
}

// MARK: - Errors

enum IPSWError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case noDestination

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid IPSW URL."
        case .httpError(let c): return "ipsw.me API returned HTTP \(c)."
        case .noDestination:    return "No download destination set."
        }
    }
}
