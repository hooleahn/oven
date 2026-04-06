import Foundation

// MARK: - Dependency definition

/// A binary dependency that Oven manages, downloads, and version-tracks.
struct Dependency: Identifiable, Codable, Sendable {
    let id: String               // e.g. "tart", "packer", "mist-cli", "jq"
    let displayName: String
    let currentVersion: String?  // nil = not yet installed
    let latestVersion: String?   // nil = not yet checked
    let binaryPath: URL          // absolute path inside deps/
    let isRequired: Bool   // false = nice-to-have; app works without it
    let status: Status

    enum Status: String, Codable, Sendable {
        case notInstalled
        case installing
        case installed
        case updateAvailable
        case error
    }

    var isReady: Bool { status == .installed || status == .updateAvailable }
}

// MARK: - Release manifest (stored as deps/versions.json)

struct DepsManifest: Codable {
    var tart: String?
    var packer: String?
    var mistCLI: String?
    var tartPackerPlugin: String?
    var jq: String?

    enum CodingKeys: String, CodingKey {
        case tart
        case packer
        case mistCLI = "mist-cli"
        case tartPackerPlugin = "tart-packer-plugin"
        case jq
    }
}
