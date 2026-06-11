import Foundation

/// Canonical OS identity used across installers, VMs, and build operations.
struct OSMetadata: Codable, Hashable, Sendable {
    var osName: MacOSRelease.Name = .unknown
    var osVersion: String = ""
    var isBeta: Bool = false
    var betaLabel: String = ""
    var customMajorVersion: String = ""   // only when osName == .custom
    var customReleaseName: String = ""    // only when osName == .custom

    init(
        osName: MacOSRelease.Name = .unknown,
        osVersion: String = "",
        isBeta: Bool = false,
        betaLabel: String = "",
        customMajorVersion: String = "",
        customReleaseName: String = ""
    ) {
        self.osName = osName
        self.osVersion = osVersion
        self.isBeta = isBeta
        self.betaLabel = betaLabel
        self.customMajorVersion = customMajorVersion
        self.customReleaseName = customReleaseName
    }

    /// Init from a fetched IPSWFirmware — infers osName from major version.
    init(from firmware: IPSWFirmware) {
        switch firmware.majorVersion {
        case 26: osName = .tahoe
        case 15: osName = .sequoia
        case 14: osName = .sonoma
        case 13: osName = .ventura
        case 12: osName = .monterey
        default: osName = .unknown
        }
        osVersion = firmware.version
    }

    /// Try to detect OS from an IPSW filename/stem, e.g. "UniversalMac_15.6.1_24H1_Restore".
    static func detect(from filename: String) -> OSMetadata? {
        let stem = (filename as NSString).deletingPathExtension
        let parts = stem.components(separatedBy: CharacterSet(charactersIn: "-_ "))
        for part in parts {
            let nums = part.components(separatedBy: ".")
            guard nums.count >= 2, let major = Int(nums[0]), major >= 12 else { continue }
            var meta = OSMetadata()
            switch major {
            case 26: meta.osName = .tahoe
            case 15: meta.osName = .sequoia
            case 14: meta.osName = .sonoma
            case 13: meta.osName = .ventura
            case 12: meta.osName = .monterey
            default: meta.osName = .unknown
            }
            meta.osVersion = part
            return meta
        }
        return nil
    }

    /// Human-readable label, e.g. "macOS Sequoia 15.6.1" or "MyOS 26.0 Beta 1".
    var displayString: String {
        let betaSuffix = isBeta ? (betaLabel.isEmpty ? " β" : " \(betaLabel)") : ""
        switch osName {
        case .unknown:
            return osVersion.isEmpty ? "Unknown" : osVersion + betaSuffix
        case .any:
            return "Any" + (osVersion.isEmpty ? "" : " \(osVersion)") + betaSuffix
        case .custom:
            let name = customReleaseName
            let vers = osVersion.isEmpty ? customMajorVersion : osVersion
            if !name.isEmpty, !vers.isEmpty { return "\(name) \(vers)\(betaSuffix)" }
            if !name.isEmpty { return name + betaSuffix }
            if !vers.isEmpty { return vers + betaSuffix }
            return "Custom OS\(betaSuffix)"
        default:
            return osVersion.isEmpty ? osName.rawValue + betaSuffix
                                     : "\(osName.rawValue) \(osVersion)\(betaSuffix)"
        }
    }
}
