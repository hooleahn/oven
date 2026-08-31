import Foundation

/// Legacy on-disk shape for a user-registered local .ipsw file, superseded by
/// `Installer` (which bridges OS identity through the shared `OSMetadata` type
/// instead of duplicating it). Kept only so `InstallerStore.load()` can decode
/// and migrate old `.customInstallers` records via `Installer(migrating:)`.
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
        addedAt: Date = Date.now
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

}
