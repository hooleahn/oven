import Foundation

// MARK: - SOFA response types
// https://sofafeed.macadmins.io/v1/macos_data_feed.json

private struct SOFAFeed: Decodable {
    let osVersions: [SOFAOSVersion]
    enum CodingKeys: String, CodingKey { case osVersions = "OSVersions" }
}

private struct SOFAOSVersion: Decodable {
    let osVersion: String               // e.g. "Sequoia 15", "Tahoe 26"
    let securityReleases: [SOFARelease]
    enum CodingKeys: String, CodingKey {
        case osVersion = "OSVersion"
        case securityReleases = "SecurityReleases"
    }
}

private struct SOFARelease: Decodable {
    let productVersion: String          // e.g. "15.4.1"
    let releaseDate: String
    enum CodingKeys: String, CodingKey {
        case productVersion = "ProductVersion"
        case releaseDate = "ReleaseDate"
    }
}

// MARK: - SOFAService

/// Fetches all released macOS versions from the SOFA feed (macadmins.io).
/// Used to populate OS/version pickers when editing VM metadata.
/// Unlike ipsw.me, SOFA lists every release — not just ones with available IPSWs.
actor SOFAService {

    static let shared = SOFAService()

    private static let feedURL = URL(string: "https://sofafeed.macadmins.io/v1/macos_data_feed.json")!
    private static let cacheFile = AppSettings.defaultLocalStorageRoot
        .appendingPathComponent("sofa-macos-cache.json")
    private static let cacheTTL: TimeInterval = 86_400   // 24 hours

    /// Cached map: MacOSRelease.Name → sorted versions, newest first
    private var cached: [MacOSRelease.Name: [String]]?
    private(set) var lastFetchDate: Date?

    // MARK: - Public API

    /// Returns all known versions for each macOS release, newest first.
    /// Falls back to MacOSRelease.Name.fallbackVersions if network unavailable.
    func versions() async -> [MacOSRelease.Name: [String]] {
        // In-memory cache
        if let cached, let date = lastFetchDate,
           Date().timeIntervalSince(date) < SOFAService.cacheTTL {
            return cached
        }
        // Disk cache
        if let (diskData, diskDate) = loadDiskCache(),
           Date().timeIntervalSince(diskDate) < SOFAService.cacheTTL {
            cached = diskData
            lastFetchDate = diskDate
            return diskData
        }
        // Network fetch
        do {
            let result = try await fetch()
            cached = result
            lastFetchDate = Date()
            saveDiskCache(result)
            return result
        } catch {
            // Network failed — return disk cache if any, else hardcoded fallbacks
            if let (diskData, _) = loadDiskCache() { return diskData }
            return fallbackVersions()
        }
    }

    /// Versions for a single release. Convenience wrapper.
    func versions(for release: MacOSRelease.Name) async -> [String] {
        await versions()[release] ?? release.fallbackVersions
    }

    func invalidateCache() {
        cached = nil
        lastFetchDate = nil
        try? FileManager.default.removeItem(at: SOFAService.cacheFile)
    }

    var isCacheFresh: Bool {
        if let date = lastFetchDate, Date().timeIntervalSince(date) < SOFAService.cacheTTL { return true }
        if let (_, diskDate) = loadDiskCache(),
           Date().timeIntervalSince(diskDate) < SOFAService.cacheTTL { return true }
        return false
    }

    // MARK: - Network

    private func fetch() async throws -> [MacOSRelease.Name: [String]] {
        var request = URLRequest(url: SOFAService.feedURL,
                                 cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Oven/1.0 (macOS VM Manager)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SOFAError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let feed = try JSONDecoder().decode(SOFAFeed.self, from: data)
        return parse(feed)
    }

    private func parse(_ feed: SOFAFeed) -> [MacOSRelease.Name: [String]] {
        var result: [MacOSRelease.Name: [String]] = [:]

        for osEntry in feed.osVersions {
            guard let release = matchRelease(osEntry.osVersion) else { continue }

            // Collect unique versions from SecurityReleases, sorted newest-first
            var seen = Set<String>()
            let versions = osEntry.securityReleases
                .map(\.productVersion)
                .filter { seen.insert($0).inserted }
                .sorted { lhs, rhs in
                    let l = lhs.split(separator: ".").compactMap { Int($0) }
                    let r = rhs.split(separator: ".").compactMap { Int($0) }
                    for (a, b) in zip(l, r) { if a != b { return a > b } }
                    return l.count > r.count
                }

            if !versions.isEmpty { result[release] = versions }
        }

        // Fill any missing releases with fallbacks
        for release in MacOSRelease.Name.allCases where result[release] == nil {
            result[release] = release.fallbackVersions
        }

        return result
    }

    /// Match SOFA's "Sequoia 15" / "Tahoe 26" string to our enum
    private func matchRelease(_ sofaName: String) -> MacOSRelease.Name? {
        let lower = sofaName.lowercased()
        if lower.contains("tahoe")    { return .tahoe }
        if lower.contains("sequoia")  { return .sequoia }
        if lower.contains("sonoma")   { return .sonoma }
        if lower.contains("ventura")  { return .ventura }
        if lower.contains("monterey") { return .monterey }
        return nil
    }

    private func fallbackVersions() -> [MacOSRelease.Name: [String]] {
        Dictionary(uniqueKeysWithValues: MacOSRelease.Name.allCases.map { ($0, $0.fallbackVersions) })
    }

    // MARK: - Disk cache

    private struct CachePayload: Codable {
        let date: Date
        // Stored as [[String]] keyed by rawValue since MacOSRelease.Name is not directly Codable as a dict key
        let entries: [String: [String]]
    }

    private func saveDiskCache(_ data: [MacOSRelease.Name: [String]]) {
        let entries = Dictionary(uniqueKeysWithValues: data.map { ($0.key.rawValue, $0.value) })
        let payload = CachePayload(date: Date(), entries: entries)
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: AppSettings.defaultLocalStorageRoot, withIntermediateDirectories: true)
        try? encoded.write(to: SOFAService.cacheFile, options: .atomic)
    }

    private func loadDiskCache() -> ([MacOSRelease.Name: [String]], Date)? {
        guard let data = try? Data(contentsOf: SOFAService.cacheFile),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return nil }
        var result: [MacOSRelease.Name: [String]] = [:]
        for (rawValue, versions) in payload.entries {
            if let release = MacOSRelease.Name(rawValue: rawValue) {
                result[release] = versions
            }
        }
        return (result, payload.date)
    }
}

// MARK: - Errors

enum SOFAError: LocalizedError {
    case httpError(Int)
    var errorDescription: String? {
        switch self {
        case .httpError(let c): return "SOFA feed returned HTTP \(c)."
        }
    }
}
