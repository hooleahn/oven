import Foundation

enum InstallerType: String, Codable, Hashable, Sendable {
    case downloaded   // fetched from ipsw.me and saved locally
    case custom       // user-provided .ipsw
}

/// A locally available macOS installer (.ipsw file) with full metadata.
struct Installer: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var osMetadata: OSMetadata
    var buildNumber: String         // e.g. "24H1"
    var releaseDate: Date?
    var sizeBytes: Int?
    var sha256: String?             // from ipsw.me for .downloaded; nil for .custom
    var downloadURL: URL?           // original ipsw.me URL; nil for .custom
    var localPath: String?          // absolute path; nil if file no longer exists
    var downloadDate: Date?
    var lastBuildDate: Date?        // last time a VM was built from this installer
    var description: String         // user notes
    var type: InstallerType
    var isManagedCopy: Bool         // true = Oven copied it to its IPSW storage

    /// Always-up-to-date computed display name: "macOS <ReleaseName> <Version>".
    /// For custom-OS installers uses customReleaseName; for known releases uses osName.rawValue.
    var displayName: String {
        let betaSuffix = osMetadata.isBeta
            ? (osMetadata.betaLabel.isEmpty ? " β" : " \(osMetadata.betaLabel)")
            : ""
        let buildSuffix = buildNumber.isEmpty ? "" : " (\(buildNumber))"
        switch osMetadata.osName {
        case .custom:
            let name = osMetadata.customReleaseName.isEmpty ? "Custom" : osMetadata.customReleaseName
            let vers = osMetadata.osVersion.isEmpty ? osMetadata.customMajorVersion : osMetadata.osVersion
            if vers.isEmpty { return "macOS \(name)\(betaSuffix)\(buildSuffix)" }
            return "macOS \(name) \(vers)\(betaSuffix)\(buildSuffix)"
        default:
            let name = osMetadata.osName == .unknown ? "" : osMetadata.osName.rawValue
            if osMetadata.osVersion.isEmpty { return "macOS \(name)\(betaSuffix)\(buildSuffix)".trimmingCharacters(in: .whitespaces) }
            return "macOS \(name) \(osMetadata.osVersion)\(betaSuffix)\(buildSuffix)".trimmingCharacters(in: .whitespaces)
        }
    }

    var fileURL: URL? { localPath.map { URL(fileURLWithPath: $0) } }
    var fileExists: Bool { localPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }

    // MARK: Migration from legacy CustomInstaller
    init(migrating legacy: CustomInstaller) {
        id = legacy.id
        osMetadata = OSMetadata(
            osName: legacy.osName,
            osVersion: legacy.osVersion,
            isBeta: legacy.isBeta,
            betaLabel: legacy.betaLabel,
            customMajorVersion: legacy.customOSMajorVersion,
            customReleaseName: legacy.customOSReleaseName
        )
        buildNumber = ""
        releaseDate = nil
        sizeBytes = nil
        sha256 = nil
        downloadURL = nil
        localPath = legacy.localPath
        downloadDate = nil
        lastBuildDate = nil
        description = legacy.displayName   // old "displayName" becomes the description/notes field
        type = .custom
        isManagedCopy = legacy.isManagedCopy
    }

    // MARK: Standard init
    init(
        id: UUID = UUID(),
        osMetadata: OSMetadata,
        buildNumber: String = "",
        releaseDate: Date? = nil,
        sizeBytes: Int? = nil,
        sha256: String? = nil,
        downloadURL: URL? = nil,
        localPath: String? = nil,
        downloadDate: Date? = nil,
        lastBuildDate: Date? = nil,
        description: String = "",
        type: InstallerType,
        isManagedCopy: Bool = false
    ) {
        self.id = id
        self.osMetadata = osMetadata
        self.buildNumber = buildNumber
        self.releaseDate = releaseDate
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.downloadDate = downloadDate
        self.lastBuildDate = lastBuildDate
        self.description = description
        self.type = type
        self.isManagedCopy = isManagedCopy
    }
}
