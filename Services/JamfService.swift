import Foundation

// MARK: - Jamf Pro API types

// JamfDevice (computers-preview) has been replaced by JamfInventoryResult
// (computers-inventory), which uses the correct string ID format and the
// non-deprecated DELETE /api/v1/computers-inventory/{id} endpoint.

// MARK: - Inventory-API types (Jamf Pro API v1/computers-inventory)

/// Lightweight result returned by the filter endpoint.
struct JamfInventoryResult: Decodable {
    let id: String   // string ID in the Pro API (e.g. "42")
    let udid: String
}

/// Management status block nested inside an inventory detail response.
struct JamfManagementStatus: Decodable {
    let enrolled: Bool
    let managed: Bool

    enum CodingKeys: String, CodingKey {
        case enrolled = "supervised"  // Jamf calls it supervised/enrolled
        case managed  = "managed"
    }
}

/// Subset of the inventory-detail response we care about.
struct JamfComputerInventory: Decodable {
    let id: String
    let udid: String
    let managementStatus: JamfManagementStatus?
    let general: JamfInventoryGeneral?
}

struct JamfInventoryGeneral: Decodable {
    let name: String?
    let lastContactTime: String?   // ISO8601
    let enrolledViaAutomatedDeviceEnrollment: Bool?
    let supervised: Bool?
    let mdmCapable: JamfMDMCapable?
}

struct JamfMDMCapable: Decodable {
    let capable: Bool
}

/// Distilled result surfaced in the UI. Codable + Hashable so it can be stored in VirtualMachine.
struct JamfEnrollmentStatus: Codable, Hashable {
    let deviceName: String?
    let enrolled: Bool
    let managed: Bool
    let mdmCapable: Bool
    let lastContact: Date?
    let enrolledViaADE: Bool

    /// Human-readable summary line.
    var summary: String {
        if enrolled && managed { return "Enrolled & Managed" }
        if enrolled            { return "Enrolled (not managed)" }
        return "Not enrolled"
    }
}

struct JamfBasicTokenResponse: Decodable {
    let token: String
    let expires: String
}

struct JamfAPITokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let scope: String
    let expires_in: Int
}

struct JamfTokenResponse: Decodable {
    let token: String
    let expires: String
}

// MARK: - Auth/privileges API types

/// Response from GET /api/v1/auth — account privileges for the current token.
struct JamfCurrentAuth: Decodable {
    let account: JamfAuthAccount?
}

struct JamfAuthAccount: Decodable {
    let username: String?
    /// Keyed by site ID (e.g. "-1" for "All Sites"); values are privilege name arrays.
    let privilegesBySite: [String: [String]]?
}

extension JamfAuthAccount {
    /// Flattens all privileges across all sites into a unique sorted list.
    var allPrivileges: [String] {
        let all = (privilegesBySite?.values.flatMap { $0 } ?? [])
        return Array(Set(all)).sorted()
    }
}

// MARK: - JamfService

actor JamfService {

    private let serverURL: URL
    private let username: String
    private let password: String
    private let credentialType: String
    private var bearerToken: String?
    private var tokenExpiry: Date?

    init(serverURL: URL, username: String, password: String, credentialType: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.credentialType = credentialType
    }

    // MARK: - Debug logging

    /// Logs a message only when Debug Mode is enabled in Preferences.
    private func debugLog(_ message: String) async {
        guard UserDefaults.standard.bool(forKey: "debugModeEnabled") else { return }
        await AppLogger.shared.log("[debug] \(message)", source: "JamfService")
    }

    // MARK: - Authentication

    private func ensureToken() async throws -> String {
        if let token = bearerToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        return try await refreshToken()
    }
    
    func refreshToken() async throws -> String {
        if credentialType == "API Client" {
            await AppLogger.shared.log("[debug] Authenticating with API Client", source: "JamfService")
            return try await refreshTokenAPIClient()
        } else {
            await AppLogger.shared.log("[debug] Authenticating with Basic credentials", source: "JamfService")
            return try await refreshTokenBasic()
        }
    }
    
    func refreshTokenAPIClient() async throws -> String {
        let url = serverURL.appendingPathComponent("api/v1/oauth/token")
        await AppLogger.shared.log("[debug] URL: \(url.absoluteString)", source: "JamfService")
        let parameters = [
          "client_id": username,
          "client_secret": password,
          "grant_type": "client_credentials",
        ]
        let joinedParameters = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let postData = Data(joinedParameters.utf8)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = postData

        let (data, response) = try await URLSession.shared.data(for: request)
                   
        let decoder = JSONDecoder()
    
//        await AppLogger.shared.log("[debug] Response: \(response)", source: "JamfService")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw JamfError.authFailed
        }
//        await AppLogger.shared.log("[debug] Data: \(data)", source: "JamfService")
        let tokenResp = try? decoder.decode(JamfAPITokenResponse.self, from: data)
        guard let decodedResponse = tokenResp else {
            await AppLogger.shared.log("Unable to parse data from response", source: "JamfService")
            return ""
        }
        bearerToken = decodedResponse.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(decodedResponse.expires_in))
        
//        await AppLogger.shared.log("[debug] Bearer Token: \(bearerToken ?? "")", source: "JamfService")
//        await AppLogger.shared.log("[debug] Token Expiry: \(tokenExpiry?.description ?? "")", source: "JamfService")
        
        return decodedResponse.access_token
    }
    
    func refreshTokenBasic() async throws -> String {
        let url = serverURL.appendingPathComponent("api/v1/auth/token")
//        await AppLogger.shared.log("[debug] URL: \(url.absoluteString)", source: "JamfService")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
//        await AppLogger.shared.log("[debug] Username: \(username) Password: REDACTED", source: "JamfService")
        guard let credData = "\(username):\(password)".data(using: .utf8) else {
            throw JamfError.authFailed
        }
        let creds = credData.base64EncodedString()
        request.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
                   
        let decoder = JSONDecoder()
    
//        await AppLogger.shared.log("[debug] Response: \(response)", source: "JamfService")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw JamfError.authFailed
        }
//        await AppLogger.shared.log("[debug] Data: \(data)", source: "JamfService")
        let tokenResp = try? decoder.decode(JamfBasicTokenResponse.self, from: data)
        guard let decodedResponse = tokenResp else {
            await AppLogger.shared.log("Unable to parse data from response", source: "JamfService")
            return ""
        }
        bearerToken = decodedResponse.token
        // Parse ISO8601 expiry
        let formatter = ISO8601DateFormatter()
        tokenExpiry = formatter.date(from: decodedResponse.expires)
        return decodedResponse.token
    }
    
    // MARK: - Keep Token Alive
    
    func keepTokenAlive() async throws -> String {
        let token = bearerToken
        let url = serverURL.appendingPathComponent("api/v1/auth/keep-alive")
        await AppLogger.shared.log("[debug] URL: \(url.absoluteString)", source: "JamfService")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token ?? "NONE")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
//        await AppLogger.shared.log("[debug] Token: \(token)", source: "JamfService")
        let (data, response) = try await URLSession.shared.data(for: request)
                   
        let decoder = JSONDecoder()
    
//        await AppLogger.shared.log("[debug] Response: \(response)", source: "JamfService")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw JamfError.authFailed
        }
//        await AppLogger.shared.log("[debug] Data: \(data)", source: "JamfService")
        let tokenResp = try? decoder.decode(JamfTokenResponse.self, from: data)
        guard let decodedResponse = tokenResp else {
            await AppLogger.shared.log("Unable to parse data from response", source: "JamfService")
            return ""
        }
        bearerToken = decodedResponse.token
        // Parse ISO8601 expiry
        let formatter = ISO8601DateFormatter()
        tokenExpiry = formatter.date(from: decodedResponse.expires)
        return decodedResponse.token
        
    }

    // MARK: - Enrollment status lookup (Jamf Pro API v1/computers-inventory)

    /// Looks up a computer by serial number and returns its enrollment status.
    /// Uses the modern Jamf Pro API (not the deprecated Classic API).
    func lookupEnrollment(serialNumber: String) async throws -> JamfEnrollmentStatus? {
        let token = try await ensureToken()

        // Step 1: filter by serial number to get the device ID
        var filterURL = serverURL.appendingPathComponent("api/v3/computers-inventory")
        filterURL = filterURL.appending(queryItems: [
            URLQueryItem(name: "filter", value: "hardware.serialNumber==\"\(serialNumber)\""),
            URLQueryItem(name: "section",  value: "GENERAL"),
        ])
        var filterReq = URLRequest(url: filterURL)
        filterReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        filterReq.setValue("application/json",  forHTTPHeaderField: "Accept")

        await debugLog("GET \(filterURL.absoluteString)")
        let (filterData, filterResp) = try await URLSession.shared.data(for: filterReq)
        guard let filterHTTP = filterResp as? HTTPURLResponse,
              (200...299).contains(filterHTTP.statusCode) else {
            if let filterHTTP = filterResp as? HTTPURLResponse {
                await debugLog("Response: HTTP \(filterHTTP.statusCode)")
            }
            throw JamfError.lookupFailed
        }
        await debugLog("Response: HTTP \(filterHTTP.statusCode)")

        struct FilterResponse: Decodable {
            let results: [JamfInventoryResult]
        }
        let filterBody = try JSONDecoder().decode(FilterResponse.self, from: filterData)
        guard let first = filterBody.results.first else {
            return nil  // device not in Jamf
        }

        // Step 2: fetch full inventory detail for that device ID
        let detailURL = serverURL.appendingPathComponent("api/v3/computers-inventory-detail/\(first.id)")
        var detailReq = URLRequest(url: detailURL)
        detailReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        detailReq.setValue("application/json",  forHTTPHeaderField: "Accept")

        let (detailData, detailResp) = try await URLSession.shared.data(for: detailReq)
        guard let detailHTTP = detailResp as? HTTPURLResponse,
              (200...299).contains(detailHTTP.statusCode) else {
            throw JamfError.lookupFailed
        }

        let decoder = JSONDecoder()
        let detail = try decoder.decode(JamfComputerInventory.self, from: detailData)

        // Parse last-contact timestamp
        var lastContact: Date? = nil
        if let ts = detail.general?.lastContactTime, !ts.isEmpty {
            lastContact = ISO8601DateFormatter().date(from: ts)
        }

        let enrolled  = detail.managementStatus?.enrolled  ?? (detail.general?.supervised ?? false)
        let managed   = detail.managementStatus?.managed   ?? false
        let mdmCap    = detail.general?.mdmCapable?.capable ?? managed
        let ade       = detail.general?.enrolledViaAutomatedDeviceEnrollment ?? false

        return JamfEnrollmentStatus(
            deviceName:    detail.general?.name,
            enrolled:      enrolled,
            managed:       managed,
            mdmCapable:    mdmCap,
            lastContact:   lastContact,
            enrolledViaADE: ade
        )
    }

    // MARK: - Device lookup

    /// Finds a computer by serial number using GET /api/v1/computers-inventory.
    /// Returns the first matching inventory record (containing the string ID needed
    /// for deletion) or nil if no computer with that serial number exists.
    func findDevice(serialNumber: String) async throws -> JamfInventoryResult? {
        let token = try await ensureToken()
        var url = serverURL.appendingPathComponent("api/v1/computers-inventory")
        url = url.appending(queryItems: [
            URLQueryItem(name: "filter",  value: "hardware.serialNumber==\"\(serialNumber)\""),
            URLQueryItem(name: "section", value: "GENERAL"),
        ])
        await debugLog("GET \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            await debugLog("Response: HTTP \(http.statusCode)")
        }
        if let body = String(data: data, encoding: .utf8) {
            await debugLog("Body: \(String(body.prefix(1000)))")
        }

        struct Response: Decodable { let results: [JamfInventoryResult] }
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        return parsed.results.first
    }

    // MARK: - Enrollment URL

    /// Generate a user-initiated enrollment URL for a specific invitation.
    func enrollmentURL(invitationCode: String) -> URL {
        serverURL
            .appendingPathComponent("enroll")
            .appending(queryItems: [URLQueryItem(name: "invitation", value: invitationCode)])
    }

    // MARK: - Remove device

    /// Removes a computer record using DELETE /api/v1/computers-inventory/{id}.
    /// The `id` is a string (as returned by the computers-inventory endpoint).
    func removeDevice(id: String) async throws {
        let token = try await ensureToken()
        let url = serverURL.appendingPathComponent("api/v1/computers-inventory/\(id)")
        await debugLog("DELETE \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse {
                await debugLog("Response: HTTP \(http.statusCode)")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    await debugLog("Body: \(String(body.prefix(500)))")
                }
            }
            throw JamfError.deleteFailed
        }
        await debugLog("Response: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) — device removed")
    }

    // MARK: - Privilege fetch

    /// Fetches the privileges granted to the current credentials.
    /// Uses GET /api/v1/auth which works for both Basic and API Client tokens.
    func fetchPrivileges() async throws -> [String] {
        let token = try await ensureToken()
        let url = serverURL.appendingPathComponent("api/v1/auth")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw JamfError.authFailed
        }
        let auth = try JSONDecoder().decode(JamfCurrentAuth.self, from: data)
        let privileges = auth.account?.allPrivileges ?? []
        await AppLogger.shared.log("[debug] Current privileges (\(privileges.count)): \(privileges.joined(separator: ", "))", source: "JamfService")
        return privileges
    }

    // MARK: - Computer Enrollment Invitation lookup (Classic API)

    /// Fetches the expiration date of a computer enrollment invitation.
    /// Uses the Classic API endpoint: GET /JSSResource/computerinvitations/invitation/{id}
    /// Returns nil if the invitation is not found or the server returns an error.
    func fetchInvitationExpiry(invitationID: String) async throws -> Date? {
        let token = try await ensureToken()
        let url = serverURL.appendingPathComponent("JSSResource/computerinvitations/invitation/\(invitationID)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        struct InvitationWrapper: Decodable {
            let computer_invitation: InvitationBody
        }
        struct InvitationBody: Decodable {
            let expiration_date_epoch: Int64?
        }

        guard let wrapper = try? JSONDecoder().decode(InvitationWrapper.self, from: data),
              let epochMs = wrapper.computer_invitation.expiration_date_epoch,
              epochMs > 0 else {
            return nil
        }
        // Jamf returns milliseconds since epoch
        return Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
    }

    // MARK: - Test connection

    func testConnection() async throws -> String {
        let token = try await refreshToken()
        let url = serverURL.appendingPathComponent("api/v1/jamf-pro-version")
//        await AppLogger.shared.log("[debug] Testing Jamf Pro connection to: \(url.absoluteString) with Token \(token)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Info: Decodable { let version: String }
        do {
            let info = try JSONDecoder().decode(Info.self, from: data)
            await AppLogger.shared.log("Jamf Pro connection test successful: \(info.version)", source: "JamfService")
            return info.version
        } catch {
            await AppLogger.shared.log("Jamf Pro connection test failed: \(error.localizedDescription)", source: "JamfService")
        }
        return "Unknown"
        
    }
}

// MARK: - Errors

enum JamfError: LocalizedError {
    case authFailed
    case deleteFailed
    case deviceNotFound
    case lookupFailed

    var errorDescription: String? {
        switch self {
        case .authFailed:    return "Jamf Pro authentication failed. Check your credentials. (See: https://developer.jamf.com/api-reference/authentication) and try again."
        case .deleteFailed:  return "Failed to remove device from Jamf Pro."
        case .deviceNotFound: return "Device not found in Jamf Pro."
        case .lookupFailed:  return "Failed to look up device in Jamf Pro. Check the server URL and permissions."
        }
    }
}
