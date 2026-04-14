import Foundation

// MARK: - MDMServer
// Represents a Jamf Pro server connection.
// The API password is stored in Keychain keyed by id.uuidString + ".password"

struct MDMServer: Identifiable, Codable, Hashable , Sendable {
    let id: UUID
    var friendlyName: String
    var serverURL: URL
    var serverAuthType: String
    var serverUsername: String
    // Password stored in Keychain — never in this struct

    // Connection test state (transient — not persisted)
    var connectionState: ConnectionState = .unknown

    enum ConnectionState: Equatable, Hashable {
        case unknown
        case testing
        case connected
        case failed(String)
    }

    // Exclude connectionState from Codable so it is never persisted.
    enum CodingKeys: String, CodingKey {
        case id, friendlyName, serverURL, serverAuthType, serverUsername
    }

    init(
        id: UUID = UUID(),
        friendlyName: String,
        serverURL: URL,
        serverAuthType: String,
        serverUsername: String
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.serverURL = serverURL
        self.serverAuthType = serverAuthType
        self.serverUsername = serverUsername
    }

    // MARK: - Keychain helpers

    var keychainKey: String { "\(id.uuidString).password" }

    var serverPassword: String? {
        get { KeychainService.retrieve(key: keychainKey) }
        nonmutating set {
            if let v = newValue {
                KeychainService.store(key: keychainKey, value: v)}
            else { KeychainService.delete(key: keychainKey) }
        }
    }

    @MainActor func makeJamfService() -> JamfService? {
        guard let pwd = serverPassword else {
            AppLogger.shared.error("No password for server: \(serverURL.absoluteString)", source: "MDMServer")
            return nil }
        AppLogger.shared.log("[debug] Using username '\(serverUsername)' and password 'REDACTED' for server: \(serverURL.absoluteString)", source: "MDMServer")
        return JamfService(serverURL: serverURL, username: serverUsername, password: pwd, credentialType: serverAuthType)
    }
}
