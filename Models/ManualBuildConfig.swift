import Foundation

// MARK: - ManualBuildConfig
//
// Complete description of a manually-configured Base VM build.
// Consumed by ManualBuildHCLGenerator to produce a .pkr.hcl file.

struct ManualBuildConfig: Codable, Hashable {
    // MARK: Identity
    var displayName: String          // shown in Oven UI
    var tartName: String             // passed to tart / packer as vm_name

    // MARK: OS
    var osName: String               // MacOSRelease.Name.rawValue
    var osVersion: String            // e.g. "15.6.1"

    // MARK: IPSW source
    var ipswSource: IPSWSource

    // MARK: Hardware
    var cpuCount: Int     = 4
    var memoryGB: Int     = 8
    var diskGB: Int       = 50

    // MARK: Setup Assistant automation
    /// When false, the VM starts at the Setup Assistant without any automation.
    var automateSetupAssistant: Bool = false

    /// ID of the BootCommandBlock to embed in the source block.
    /// Only meaningful when automateSetupAssistant == true.
    var bootCommandBlockID: UUID? = nil

    // MARK: Credentials (only used when automateSetupAssistant == true)
    var credentials: VMCredentials = .init()

    // MARK: Provisioning (only used when automateSetupAssistant == true)
    var provisioning: ProvisioningOptions = .init()

    // MARK: MDM enrollment (only used when automateSetupAssistant == true)
    /// ID of the MDMProfile to enroll during provisioning. nil = no enrollment.
    var mdmProfileID: UUID? = nil
}

// MARK: - IPSWSource

enum IPSWSource: Hashable, Codable {
    /// Resolved at build time via SOFA / Mist using osName + osVersion.
    case auto
    /// A local .ipsw file the user picked from Finder.
    case filePath(URL)
    /// A remote URL the user typed in.
    case url(String)

    var displayLabel: String {
        switch self {
        case .auto:              return "Auto (SOFA / Mist)"
        case .filePath(let u):  return u.lastPathComponent
        case .url(let s):       return s
        }
    }

    /// The string to embed in the generated HCL as ipsw_url / from_ipsw.
    /// For .auto the caller is responsible for resolving the URL before
    /// passing it to the generator.
    var hclValue: String {
        switch self {
        case .auto:             return ""          // caller must resolve first
        case .filePath(let u): return u.path
        case .url(let s):      return s
        }
    }
}

// MARK: - VMCredentials

struct VMCredentials: Codable, Hashable {
    var username: String = "admin"
    var password: String = "admin"
}

// MARK: - ProvisioningOptions

struct ProvisioningOptions: Codable, Hashable {
    // Security
    var passwordlessSudo: Bool  = true
    var disableGatekeeper: Bool = true   // handled in boot_command; kept here for generated-template clarity

    // Session
    var autoLogin: Bool         = true
    var disableSleep: Bool      = true
    var disableScreenLock: Bool = true

    // Indexing
    var disableSpotlight: Bool  = false

    // Developer tools (dependency-ordered)
    var installCLITools: Bool   = true
    var installHomebrew: Bool   = false  // requires installCLITools
    var installXcode: Bool      = false  // requires installHomebrew (full Xcode via Homebrew cask)

    // Automation
    var safariAutomation: Bool  = false

    // Tart integration
    var tartGuestAgent: Bool    = false  // requires installHomebrew

    // File uploads
    var fileUploads: [FileUpload] = []

    // MARK: Dependency enforcement

    /// Enforces the dependency chain so the caller doesn't have to.
    /// Call after any toggle change to keep options consistent.
    mutating func enforceDependencies() {
        if installXcode     { installHomebrew = true }
        if tartGuestAgent   { installHomebrew = true }
        if installHomebrew  { installCLITools = true }
    }
}

// MARK: - FileUpload

struct FileUpload: Identifiable, Codable, Hashable {
    var id: UUID       = UUID()
    var sourcePath: String      = ""
    var destinationPath: String = "/tmp/"
}
