import Foundation

struct MDMProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var profileDescription: String
    /// nil means "Custom" (no linked server)
    var serverID: UUID?
    /// For custom mode, the user provides the full MDM server URL
    var customServerURL: String
    var invitationID: String
    var expirationDate: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        profileDescription: String = "",
        serverID: UUID? = nil,
        customServerURL: String = "",
        invitationID: String = "",
        expirationDate: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.profileDescription = profileDescription
        self.serverID = serverID
        self.customServerURL = customServerURL
        self.invitationID = invitationID
        self.expirationDate = expirationDate
    }

    /// Returns true when the invitation is not yet expired (or has no expiration date set).
    var isValid: Bool {
        guard let exp = expirationDate else { return true }
        return exp > Date()
    }
}
