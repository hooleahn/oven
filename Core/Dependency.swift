import Foundation

// MARK: - Dependency definition

struct Dependency: Identifiable, Codable, Sendable {
    let id: String               // e.g. "tart", "packer", "mist-cli", "jq"
    let displayName: String
    let purpose: String          // Human-readable description of what the tool does
    let icon: String             // SF Symbol name
    var currentVersion: String?  // nil = not yet installed
    var latestVersion: String?   // nil = not yet checked
    var binaryPath: URL          // absolute path inside deps/ (managed fallback)
    let isRequired: Bool         // false = nice-to-have; app works without it
    let requiredForLaunch: Bool  // false = can skip; app opens but feature is limited
    let installURL: URL?         // GitHub release page for manual reference
    var installMethod: AppSettings.DependencyInstallSetting.Method = .managed
    var customPath: String = ""  // effective path when installMethod == .custom
    var detectedSystemPath: URL? // Binary found on the OS at launch (e.g. via Homebrew)
    var status: Status

    enum Status: String, Codable, Sendable {
        case notInstalled
        case installing
        case installed
        case updateAvailable
        case skipped            // User chose to skip this dependency
        case error
    }

    var isReady: Bool { status == .installed || status == .updateAvailable }

    /// The effective binary location shown to the user.
    var location: String? {
        switch installMethod {
        case .custom:
            return customPath.isEmpty ? nil : customPath
        case .managed:
            guard isReady else { return nil }
            return binaryPath.path
        }
    }

    /// Version string to display (version or "—")
    var displayVersion: String {
        currentVersion ?? "—"
    }
}

// MARK: - Release manifest (stored as deps/versions.json)

struct DepsManifest: Codable {
    var tart: String?
    var packer: String?
    var mistCLI: String?
    var tartPackerPlugin: String?
    var jq: String?
    var sshpass: String?

    enum CodingKeys: String, CodingKey {
        case tart
        case packer
        case mistCLI = "mist-cli"
        case tartPackerPlugin = "tart-packer-plugin"
        case jq
        case sshpass
    }
}
