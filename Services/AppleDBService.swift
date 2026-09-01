import Foundation

// MARK: - AppleDBService
//
// Neither mist-cli nor ipsw.me ever list Apple's developer/public betas — they
// only track final public releases. appledb.dev is a community-maintained
// catalogue that tracks every build Apple has shipped, including betas and RCs,
// keyed per device. This fetches just the entries relevant to tart VMs
// (device identifier "VirtualMac2,1") and narrows them to beta/RC builds that
// are currently signed (and thus actually restorable) — the gap the other two
// sources leave open.

actor AppleDBService {

    static let shared = AppleDBService()

    private let deviceIdentifier = "VirtualMac2,1"
    private static let cacheFile = AppSettings.defaultLocalStorageRoot
        .appendingPathComponent("appledb-firmware-cache.json")
    // Betas move fast (new seeds roughly weekly) and old ones stop being signed
    // within days — cache for a shorter window than the 24h used for stable
    // releases so a stale "signed" build doesn't linger in the list.
    private static let cacheTTL: TimeInterval = 3_600

    private var cachedFirmwares: [IPSWFirmware]?
    private(set) var lastFetchDate: Date?

    // MARK: - Firmware list

    /// Currently-signed beta/RC firmware for VirtualMac2,1, sourced from appledb.dev.
    func listBetaFirmware() async throws -> [IPSWFirmware] {
        if let cached = cachedFirmwares, let date = lastFetchDate,
           Date.now.timeIntervalSince(date) < Self.cacheTTL {
            return cached
        }
        if let (diskFirmwares, diskDate) = loadDiskCache(),
           Date.now.timeIntervalSince(diskDate) < Self.cacheTTL {
            cachedFirmwares = diskFirmwares
            lastFetchDate = diskDate
            return diskFirmwares
        }

        let urlString = "https://appledb.dev/pageData/device/identifier/\(deviceIdentifier).json"
        guard let url = URL(string: urlString) else { throw AppleDBError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppleDBError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let page = try JSONDecoder().decode(AppleDBPage.self, from: data)

        let firmwares: [IPSWFirmware] = page.frontmatter.versionArr.compactMap { entry in
            guard entry.osStr == "macOS", entry.beta || entry.rc else { return nil }
            guard entry.signed.contains(deviceIdentifier) else { return nil }
            guard let download = entry.downloads.first(where: { $0.key == deviceIdentifier }),
                  !download.url.isEmpty else { return nil }

            let (cleanVersion, label) = Self.parseVersion(entry.version, isRC: entry.rc)
            return IPSWFirmware(
                identifier: deviceIdentifier,
                version: cleanVersion,
                buildid: entry.build,
                sha256sum: "",
                filesize: 0,
                url: download.url,
                releasedate: entry.released,
                signed: true,
                isBeta: true,
                betaLabel: label,
                source: .appleDB
            )
        }

        // AppleDB occasionally lists the same build under more than one
        // re-seeded version entry — keep the first (newest, since versionArr
        // is already newest-first).
        var seen = Set<String>()
        let deduped = firmwares.filter { seen.insert($0.buildid).inserted }

        cachedFirmwares = deduped
        lastFetchDate = Date.now
        saveDiskCache(deduped)
        return deduped
    }

    /// Force-expire the cache. Call when the user toggles the setting on or hits Refresh.
    func invalidateCache() {
        cachedFirmwares = nil
        lastFetchDate = nil
        try? FileManager.default.removeItem(at: Self.cacheFile)
    }

    // MARK: - Version parsing
    // AppleDB embeds pre-release status in the version string itself, e.g.
    // "27.0 beta 8", "26.7 RC 3", "26.6.2 RC" — split into a clean dotted
    // version (safe for the digits-and-dots validation used elsewhere in Oven)
    // and a display label ("Beta 8", "RC 3", "RC").
    private static func parseVersion(_ raw: String, isRC: Bool) -> (version: String, label: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: #"^\d+(\.\d+)*"#, options: .regularExpression) else {
            return (trimmed, isRC ? "RC" : "Beta")
        }
        let version = String(trimmed[match])
        let suffix = trimmed[match.upperBound...].trimmingCharacters(in: .whitespaces)
        if isRC {
            return (version, suffix.isEmpty ? "RC" : suffix)
        }
        if suffix.lowercased().hasPrefix("beta") {
            return (version, "Beta" + suffix.dropFirst(4))
        }
        return (version, suffix.isEmpty ? "Beta" : suffix)
    }

    // MARK: - Disk persistence

    private func saveDiskCache(_ firmwares: [IPSWFirmware]) {
        let payload = CachePayload(date: Date.now, firmwares: firmwares)
        if let data = try? JSONEncoder().encode(payload) {
            try? FileManager.default.createDirectory(
                at: AppSettings.defaultLocalStorageRoot, withIntermediateDirectories: true)
            try? data.write(to: Self.cacheFile, options: .atomic)
        }
    }

    private func loadDiskCache() -> ([IPSWFirmware], Date)? {
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return nil }
        return (payload.firmwares, payload.date)
    }

    private struct CachePayload: Codable {
        let date: Date
        let firmwares: [IPSWFirmware]
    }
}

// MARK: - AppleDB page schema
// Only the fields Oven actually needs — appledb.dev's pageData JSON carries a
// lot more (jailbreak compatibility, OTA info, signing lists for every Mac
// model, …) that Codable simply ignores.

private struct AppleDBPage: Decodable {
    let frontmatter: Frontmatter

    struct Frontmatter: Decodable {
        let versionArr: [VersionEntry]
    }

    // Some historical entries in AppleDB's dataset (old/withdrawn seeds near
    // the end of versionArr) are missing fields entries newer ones always
    // have. A field-by-field `decodeIfPresent` with defaults means one
    // incomplete old record just decodes to something our filters naturally
    // exclude, rather than throwing and losing the entire fetch — a single
    // required field missing on any of the ~500+ entries here previously
    // took down the whole appledb.dev integration.
    struct VersionEntry: Decodable {
        let osStr: String
        let version: String
        let build: String
        let released: String
        let beta: Bool
        let rc: Bool
        let signed: [String]
        let downloads: [Download]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            osStr     = try c.decodeIfPresent(String.self, forKey: .osStr) ?? ""
            version   = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
            build     = try c.decodeIfPresent(String.self, forKey: .build) ?? ""
            released  = try c.decodeIfPresent(String.self, forKey: .released) ?? ""
            beta      = try c.decodeIfPresent(Bool.self, forKey: .beta) ?? false
            rc        = try c.decodeIfPresent(Bool.self, forKey: .rc) ?? false
            signed    = try c.decodeIfPresent([String].self, forKey: .signed) ?? []
            downloads = try c.decodeIfPresent([Download].self, forKey: .downloads) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case osStr, version, build, released, beta, rc, signed, downloads
        }
    }

    struct Download: Decodable {
        let key: String
        let url: String

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
            url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case key, url
        }
    }
}

// MARK: - Errors

enum AppleDBError: LocalizedError {
    case invalidURL
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid appledb.dev URL."
        case .httpError(let c): return "appledb.dev returned HTTP \(c)."
        }
    }
}
