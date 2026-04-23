import Foundation

// MARK: - VirtualMachine

/// A tart VM instance. The `name` field is the tart identifier — it must be
/// unique and is used for all tart CLI calls.
struct VirtualMachine: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var displayName: String        // human label, defaults to name
    var description: String
    var tags: [String]
    var status: Status
    var baseVMID: UUID?            // nil = created from registry image directly
    var mdmProfileID: UUID?
    var cpuCount: Int
    var memoryGB: Int
    var diskGB: Int
    var macOSVersion: String
    var serialNumber: String
    var ipAddress: String?
    var createdAt: Date
    var lastStartedAt: Date?
    var registryImageRef: String?  // origin ref if pulled from a registry
    var isBaseVM: Bool = false          // true = Base VM (can clone, cannot start)

    // Build metadata (only relevant when isBaseVM == true)
    var osName: MacOSRelease.Name = .unknown
    var osVersion: String = ""          // e.g. "15.3.2"
    var ipswLocalPath: String?
    var ipswRemoteURL: String?
    var installRosetta: Bool = true
    var installHomebrew: Bool = true
    var enableSSHDaemon: Bool = true
    var enableAutoLogin: Bool = true
    var enablePasswordlessSudo: Bool = true
    var xcodeVersion: String?
    var builtAt: Date?
    var buildLog: [String] = []
    var packerTemplateName: String = ""
    var packerVarsName: String = ""
    var customTemplatePath: String?   // legacy — kept for migration from v4
    var customTemplateID: UUID?       // v5+: references PackerTemplate by metadata ID
    var customVarsFileID: UUID?       // v5+: references a .pkrvars.hcl by metadata ID
    var manualBuildConfig: ManualBuildConfig?  // non-nil = was created via manual build path
    var vmSource: VMSource = .local   // avoids clash with SwiftUI .local

    enum VMSource: String, Codable, Hashable {
        case local    = "Built locally"
        case registry = "From registry"
    }

    // Build status (separate from running status)
    var buildStatus: BuildStatus = .notBuilt

    enum BuildStatus: String, Codable, Hashable {
        case notBuilt, building, ready, error

        var label: String {
            switch self {
            case .notBuilt: return "Not built"
            case .building: return "Building"
            case .ready:    return "Ready"
            case .error:    return "Error"
            }
        }
        var systemImage: String {
            switch self {
            case .notBuilt: return "shippingbox"
            case .building: return "arrow.triangle.2.circlepath"
            case .ready:    return "checkmark.seal.fill"
            case .error:    return "exclamationmark.triangle.fill"
            }
        }
    }
    var mdmServerID: UUID?         // MDM server used during enrollment
    var sharedFolders: [SharedFolder] = []
    var sshUsername: String = "baker"  // username for SSH access

    // Password stored in Keychain (never serialised to disk)
    var keychainKey: String { "vm.\(id.uuidString).password" }
    var sshPassword: String? {
        get { KeychainService.retrieve(key: keychainKey) }
        set {
            if let v = newValue, !v.isEmpty { KeychainService.store(key: keychainKey, value: v) }
            else { KeychainService.delete(key: keychainKey) }
        }
    }
    /// OCI-sourced VMs are always base VMs regardless of isBaseVM flag
    var isOCIBased: Bool { registryImageRef != nil }
    /// True if this VM acts as a Base VM (can clone, cannot start)
    var effectivelyBase: Bool { isBaseVM || isOCIBased }

    // MARK: - Base VM naming helpers
    static func autoName(osName: MacOSRelease.Name, version: String) -> String {
        let os = osName.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        guard !version.isEmpty else { return "base-\(os)-select-version" }
        return "base-\(os)-\(version)"
    }

    static func uniqueAutoName(osName: MacOSRelease.Name, version: String,
                               existing: [VirtualMachine]) -> String {
        let base = autoName(osName: osName, version: version)
        guard existing.contains(where: { $0.name == base }) else { return base }
        for counter in 2...99 {
            let candidate = base + "-\(counter)"
            if !existing.contains(where: { $0.name == candidate }) { return candidate }
        }
        return base + "-" + String(UUID().uuidString.prefix(4).lowercased())
    }

    var isResolvingIP: Bool = false    // true while polling for IP
    var isStopping: Bool = false       // true while tart stop is in flight
    var actualDiskGB: Int? = nil       // from tart list Size field, nil if unknown

    // MARK: - SharedFolder
    struct SharedFolder: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        var name: String      // mount name inside the VM
        var hostPath: String  // absolute path on the host
        var readOnly: Bool

        init(id: UUID = UUID(), name: String, hostPath: String, readOnly: Bool = true) {
            self.id = id; self.name = name; self.hostPath = hostPath; self.readOnly = readOnly
        }

        /// Argument for `tart run --dir`
        var tartArg: String {
            readOnly ? "\(name):\(hostPath):ro" : "\(name):\(hostPath)"
        }
    }

    // MARK: Status

    enum Status: String, Codable, Hashable {
        case stopped
        case running
        case suspended
        case building   // being created/cloned right now
        case error

        var label: String {
            switch self {
            case .stopped:   return "Stopped"
            case .running:   return "Running"
            case .suspended: return "Suspended"
            case .building:  return "Building"
            case .error:     return "Error"
            }
        }

        var systemImage: String {
            switch self {
            case .stopped:   return "stop.circle"
            case .running:   return "play.circle.fill"
            case .suspended: return "pause.circle.fill"
            case .building:  return "arrow.triangle.2.circlepath"
            case .error:     return "exclamationmark.circle.fill"
            }
        }

        /// Initialise from the string tart emits in `tart list`
        init(tartState: String) {
            switch tartState.lowercased() {
            case "running":   self = .running
            case "suspended": self = .suspended
            default:          self = .stopped
            }
        }
    }

    // MARK: - Convenience init from tart list output

    init(fromTart info: TartVMInfo) {
        self.id               = UUID()
        self.name             = info.name
        self.displayName      = info.name
        self.description      = ""
        self.tags             = []
        self.status           = Status(tartState: info.state)
        self.baseVMID         = nil
        self.mdmProfileID     = nil
        self.cpuCount         = 4
        self.memoryGB         = 8
        self.diskGB           = 80
        self.serialNumber     = ""
        self.macOSVersion     = ""
        self.ipAddress        = nil
        self.createdAt        = Date()
        self.lastStartedAt    = nil
        // Only set registryImageRef if the VM name itself is an OCI ref (contains "/").
        // info.source for local clones is the OCI origin — useful for provenance
        // but does not make this VM an OCI image (isOCIBased must stay false for local VMs).
        self.registryImageRef = info.name.contains("/") ? info.source : nil
    }

    // MARK: - Codable migration
    // Use decodeIfPresent for all fields added after v0.1.060 so that VMs
    // saved by older builds still decode correctly.

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,                   forKey: .id)
        name             = try c.decode(String.self,                 forKey: .name)
        displayName      = try c.decode(String.self,                 forKey: .displayName)
        description      = try c.decodeIfPresent(String.self,        forKey: .description)      ?? ""
        tags             = try c.decodeIfPresent([String].self,       forKey: .tags)             ?? []
        status           = try c.decode(Status.self,                 forKey: .status)
        baseVMID         = try c.decodeIfPresent(UUID.self,           forKey: .baseVMID)
        mdmProfileID     = try c.decodeIfPresent(UUID.self,           forKey: .mdmProfileID)
        cpuCount         = try c.decodeIfPresent(Int.self,            forKey: .cpuCount)         ?? 4
        memoryGB         = try c.decodeIfPresent(Int.self,            forKey: .memoryGB)         ?? 8
        diskGB           = try c.decodeIfPresent(Int.self,            forKey: .diskGB)           ?? 80
        serialNumber     = try c.decodeIfPresent(String.self,        forKey: .serialNumber)     ?? ""
        macOSVersion     = try c.decodeIfPresent(String.self,        forKey: .macOSVersion)     ?? ""
        ipAddress        = try c.decodeIfPresent(String.self,        forKey: .ipAddress)
        createdAt        = try c.decodeIfPresent(Date.self,           forKey: .createdAt)        ?? Date()
        lastStartedAt    = try c.decodeIfPresent(Date.self,           forKey: .lastStartedAt)
        registryImageRef = try c.decodeIfPresent(String.self,        forKey: .registryImageRef)
        isBaseVM         = try c.decodeIfPresent(Bool.self,           forKey: .isBaseVM) ?? false
        osName              = try c.decodeIfPresent(MacOSRelease.Name.self, forKey: .osName) ?? .unknown
        osVersion           = try c.decodeIfPresent(String.self,              forKey: .osVersion) ?? ""
        ipswLocalPath       = try c.decodeIfPresent(String.self,   forKey: .ipswLocalPath)
        ipswRemoteURL       = try c.decodeIfPresent(String.self,   forKey: .ipswRemoteURL)
        installRosetta      = try c.decodeIfPresent(Bool.self,     forKey: .installRosetta) ?? true
        installHomebrew     = try c.decodeIfPresent(Bool.self,     forKey: .installHomebrew) ?? true
        enableSSHDaemon     = try c.decodeIfPresent(Bool.self,     forKey: .enableSSHDaemon) ?? true
        enableAutoLogin     = try c.decodeIfPresent(Bool.self,     forKey: .enableAutoLogin) ?? true
        enablePasswordlessSudo = try c.decodeIfPresent(Bool.self,  forKey: .enablePasswordlessSudo) ?? true
        xcodeVersion        = try c.decodeIfPresent(String.self,   forKey: .xcodeVersion)
        builtAt             = try c.decodeIfPresent(Date.self,     forKey: .builtAt)
        buildLog            = try c.decodeIfPresent([String].self, forKey: .buildLog) ?? []
        packerTemplateName  = try c.decodeIfPresent(String.self,   forKey: .packerTemplateName) ?? ""
        packerVarsName      = try c.decodeIfPresent(String.self,   forKey: .packerVarsName) ?? ""
        customTemplatePath  = try c.decodeIfPresent(String.self,   forKey: .customTemplatePath)
        customTemplateID    = try c.decodeIfPresent(UUID.self,     forKey: .customTemplateID)
        customVarsFileID    = try c.decodeIfPresent(UUID.self,     forKey: .customVarsFileID)
        vmSource            = try c.decodeIfPresent(VMSource.self, forKey: .vmSource) ?? .local
        buildStatus         = try c.decodeIfPresent(BuildStatus.self, forKey: .buildStatus) ?? .notBuilt
        mdmServerID      = try c.decodeIfPresent(UUID.self,           forKey: .mdmServerID)
        sharedFolders    = try c.decodeIfPresent([SharedFolder].self,  forKey: .sharedFolders)   ?? []
        sshUsername      = try c.decodeIfPresent(String.self,         forKey: .sshUsername)      ?? "baker"
        manualBuildConfig = try c.decodeIfPresent(ManualBuildConfig.self, forKey: .manualBuildConfig)
        isResolvingIP    = false  // always reset on load — never persisted
        isStopping       = false
    }

    // MARK: - Full init

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        description: String = "",
        tags: [String] = [],
        status: Status = .stopped,
        baseVMID: UUID? = nil,
        mdmProfileID: UUID? = nil,
        cpuCount: Int = 4,
        memoryGB: Int = 8,
        diskGB: Int = 80,
        serialNumber: String = "",
        macOSVersion: String = "",
        ipAddress: String? = nil,
        createdAt: Date = Date(),
        lastStartedAt: Date? = nil,
        registryImageRef: String? = nil,
        isBaseVM: Bool = false,
        mdmServerID: UUID? = nil,
        sharedFolders: [SharedFolder] = [],
        sshUsername: String = "baker"
    ) {  // isResolvingIP is transient, not an init param
        self.id               = id
        self.name             = name
        self.displayName      = displayName ?? name
        self.description      = description
        self.tags             = tags
        self.status           = status
        self.baseVMID         = baseVMID
        self.mdmProfileID     = mdmProfileID
        self.cpuCount         = cpuCount
        self.memoryGB         = memoryGB
        self.diskGB           = diskGB
        self.serialNumber     = serialNumber
        self.macOSVersion     = macOSVersion
        self.ipAddress        = ipAddress
        self.createdAt        = createdAt
        self.lastStartedAt    = lastStartedAt
        self.registryImageRef = registryImageRef
        self.isBaseVM         = isBaseVM
        self.mdmServerID      = mdmServerID
        self.sharedFolders    = sharedFolders
        self.sshUsername      = sshUsername
        self.isResolvingIP    = false
    }
}

// MARK: - macOS release catalogue
// Versions shown in pickers. These are static fallbacks used when mist-cli
// hasn't been called yet or is unavailable. The Base VM sheet fetches the
// live list from mist-cli via MistService.listFirmware() on appear.

struct MacOSRelease {
    enum Name: String, Codable, Hashable, CaseIterable {
        case tahoe    = "Tahoe"
        case sequoia  = "Sequoia"
        case sonoma   = "Sonoma"
        case ventura  = "Ventura"
        case monterey = "Monterey"
        case unknown  = "Unknown"

        // Major version prefix used to filter mist-cli results
        var majorVersion: Int {
            switch self {
            case .tahoe:    return 26
            case .sequoia:  return 15
            case .sonoma:   return 14
            case .ventura:  return 13
            case .monterey: return 12
            case .unknown:  return 0
            }
        }

        // Display label including the version number for clarity
        var displayLabel: String {
            switch self {
            case .tahoe:    return "macOS 26 Tahoe"
            case .sequoia:  return "macOS 15 Sequoia"
            case .sonoma:   return "macOS 14 Sonoma"
            case .ventura:  return "macOS 13 Ventura"
            case .monterey: return "macOS 12 Monterey"
            case .unknown:  return "Unknown"
            }
        }

        // Fallback versions — never includes "latest" (ambiguous)
        var fallbackVersions: [String] {
            switch self {
            case .tahoe:    return ["26.4","26.3.1","26.3","26.2","26.1","26.0"]
            case .sequoia:  return ["15.5","15.4.1","15.4","15.3.2","15.3.1","15.3","15.2","15.1","15.0"]
            case .sonoma:   return ["14.7.6","14.7.5","14.7.4","14.7.3","14.7.2","14.7.1","14.7","14.6.1","14.6","14.5","14.4.1","14.4","14.3.1","14.3","14.2.1","14.2","14.1.2","14.1.1","14.1","14.0"]
            case .ventura:  return ["13.7.5","13.7.4","13.7.3","13.7.2","13.7.1","13.7","13.6.9","13.6.8","13.6.7","13.6.6","13.6.5","13.6.4","13.6.3","13.6.2","13.6.1","13.6"]
            case .monterey: return ["12.7.6","12.7.5","12.7.4","12.7.3","12.7.2","12.7.1","12.7","12.6.8","12.6.7","12.6.6","12.6.5"]
            case .unknown:  return []
            }
        }

        // For backward compatibility in existing callers
        var versions: [String] { fallbackVersions }
    }
}
