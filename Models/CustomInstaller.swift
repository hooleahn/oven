import Foundation

/// A user-registered local .ipsw file with OS metadata.
/// Used for betas and other firmwares not available via ipsw.me or mist-cli.
struct CustomInstaller: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String           // user-provided label, e.g. "macOS 26 Beta 2"
    var osName: MacOSRelease.Name     // .custom or a known release
    var customOSReleaseName: String   // only used when osName == .custom
    var customOSMajorVersion: String  // only used when osName == .custom
    var osVersion: String             // e.g. "26.5"
    var isBeta: Bool
    var betaLabel: String             // e.g. "Beta 1", "RC 2"
    var localPath: String             // absolute path to the .ipsw file
    var isManagedCopy: Bool           // true = Oven copied it to its IPSW storage
    var addedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        osName: MacOSRelease.Name,
        customOSReleaseName: String = "",
        customOSMajorVersion: String = "",
        osVersion: String = "",
        isBeta: Bool = false,
        betaLabel: String = "",
        localPath: String,
        isManagedCopy: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.osName = osName
        self.customOSReleaseName = customOSReleaseName
        self.customOSMajorVersion = customOSMajorVersion
        self.osVersion = osVersion
        self.isBeta = isBeta
        self.betaLabel = betaLabel
        self.localPath = localPath
        self.isManagedCopy = isManagedCopy
        self.addedAt = addedAt
    }

    var fileURL: URL { URL(fileURLWithPath: localPath) }

    var fileExists: Bool { FileManager.default.fileExists(atPath: localPath) }

    var osDisplayLabel: String {
        let betaSuffix = isBeta ? (betaLabel.isEmpty ? " β" : " \(betaLabel)") : ""
        switch osName {
        case .custom:
            let name = customOSReleaseName
            let vers = osVersion.isEmpty ? customOSMajorVersion : osVersion
            if !name.isEmpty && !vers.isEmpty { return "\(name) \(vers)\(betaSuffix)" }
            if !name.isEmpty { return name + betaSuffix }
            if !vers.isEmpty { return vers + betaSuffix }
            return "Custom OS\(betaSuffix)"
        default:
            if osVersion.isEmpty { return osName.rawValue + betaSuffix }
            return "\(osName.rawValue) \(osVersion)\(betaSuffix)"
        }
    }
}
