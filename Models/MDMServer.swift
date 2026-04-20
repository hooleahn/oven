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

    // Persisted test result fields
    var storedPrivileges: [String] = []
    var lastTestResult: String? = nil
    var lastTestedAt: Date? = nil

    // Per-server feature toggles (all enabled by default)
    var featureCheckEnrollment: Bool = true
    var featureDeleteFromJamf: Bool = true
    var featureCheckInvitationStatus: Bool = true

    enum ConnectionState: Equatable, Hashable {
        case unknown
        case testing
        case connected
        case failed(String)
    }

    // connectionState is transient; all other fields are persisted.
    enum CodingKeys: String, CodingKey {
        case id, friendlyName, serverURL, serverAuthType, serverUsername
        case storedPrivileges, lastTestResult, lastTestedAt
        case featureCheckEnrollment, featureDeleteFromJamf, featureCheckInvitationStatus
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        friendlyName = try c.decode(String.self, forKey: .friendlyName)
        serverURL = try c.decode(URL.self, forKey: .serverURL)
        serverAuthType = try c.decode(String.self, forKey: .serverAuthType)
        serverUsername = try c.decode(String.self, forKey: .serverUsername)
        storedPrivileges = (try? c.decode([String].self, forKey: .storedPrivileges)) ?? []
        lastTestResult   = try? c.decode(String.self, forKey: .lastTestResult)
        lastTestedAt     = try? c.decode(Date.self,   forKey: .lastTestedAt)
        featureCheckEnrollment      = (try? c.decode(Bool.self, forKey: .featureCheckEnrollment))      ?? true
        featureDeleteFromJamf       = (try? c.decode(Bool.self, forKey: .featureDeleteFromJamf))       ?? true
        featureCheckInvitationStatus = (try? c.decode(Bool.self, forKey: .featureCheckInvitationStatus)) ?? true

        // Restore connection state from the last persisted test result so the
        // row icon is correct immediately after an app restart.
        if let result = lastTestResult {
            connectionState = result.hasPrefix("✓") ? .connected : .failed(result)
        }
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
