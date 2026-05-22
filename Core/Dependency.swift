import Foundation

// MARK: - Dependency definition

/// A binary dependency that Oven manages, downloads, and version-tracks.
struct Dependency: Identifiable, Codable, Sendable {
    let id: String               // e.g. "tart", "packer", "mist-cli", "jq"
    let displayName: String
    let purpose: String          // Human-readable description of what the tool does
    let icon: String             // SF Symbol name
    var currentVersion: String?  // nil = not yet installed
    var latestVersion: String?   // nil = not yet checked
    var binaryPath: URL          // absolute path inside deps/ (managed) or user-chosen
    let isRequired: Bool         // false = nice-to-have; app works without it
    let requiredForLaunch: Bool  // false = can skip; app opens but feature is limited
    let installURL: URL?         // GitHub release page for manual reference
    var systemBinaryPath: URL?   // User-supplied override path (from "Use system binary…")
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
        if let sys = systemBinaryPath { return sys.path }
        guard isReady else { return nil }
        return binaryPath.path
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
