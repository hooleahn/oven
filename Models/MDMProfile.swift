import Foundation

struct MDMProfile: Identifiable, Codable, Hashable , Sendable {
    let id: UUID
    var name: String
    var serverID: UUID              // references MDMServer.id
    var invitationID: String        // Jamf Pro Enrollment Invitation ID
    var enrollmentType: EnrollmentType
    var site: String?
    var department: String?
    var smartGroup: String?
    var tokenLifetimeDays: Int
    var autoRenewToken: Bool
    var runPolicyOnEnroll: Bool
    var enrollmentPolicyName: String?
    var isActive: Bool
    var tokenExpiresAt: Date?

    enum EnrollmentType: String, Codable, CaseIterable, Hashable {
        case profile = "Profile (desktop)"
        case link    = "Link (URL)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        serverID: UUID,
        invitationID: String = "",
        enrollmentType: EnrollmentType = .profile,
        site: String? = nil,
        department: String? = nil,
        smartGroup: String? = nil,
        tokenLifetimeDays: Int = 30,
        autoRenewToken: Bool = true,
        runPolicyOnEnroll: Bool = false,
        enrollmentPolicyName: String? = nil,
        isActive: Bool = true,
        tokenExpiresAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.serverID = serverID
        self.invitationID = invitationID
        self.enrollmentType = enrollmentType
        self.site = site
        self.department = department
        self.smartGroup = smartGroup
        self.tokenLifetimeDays = tokenLifetimeDays
        self.autoRenewToken = autoRenewToken
        self.runPolicyOnEnroll = runPolicyOnEnroll
        self.enrollmentPolicyName = enrollmentPolicyName
        self.isActive = isActive
        self.tokenExpiresAt = tokenExpiresAt
    }
}
