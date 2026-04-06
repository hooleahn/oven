import Foundation

// MARK: - Jamf Pro API types

struct JamfDevice: Decodable {
    let id: Int
    let name: String
    let serialNumber: String
    let udid: String
    let managed: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case serialNumber = "serialNumber"
        case udid = "udid"
        case managed = "managementStatus"
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

    // MARK: - Device lookup

    func findDevice(serialNumber: String) async throws -> JamfDevice? {
        let token = try await ensureToken()
        let url = serverURL.appendingPathComponent("api/v1/computers-preview")
            .appending(queryItems: [URLQueryItem(name: "filter", value: "serialNumber==\(serialNumber)")])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable { let results: [JamfDevice] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.results.first
    }

    // MARK: - Enrollment URL

    /// Generate a user-initiated enrollment URL for a specific invitation.
    func enrollmentURL(invitationCode: String) -> URL {
        serverURL
            .appendingPathComponent("enroll")
            .appending(queryItems: [URLQueryItem(name: "invitation", value: invitationCode)])
    }

    // MARK: - Remove device

    func removeDevice(id: Int) async throws {
        let token = try await ensureToken()
        let url = serverURL.appendingPathComponent("api/v1/computers/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw JamfError.deleteFailed
        }
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

    var errorDescription: String? {
        switch self {
        case .authFailed:    return "Jamf Pro authentication failed. Check your credentials. (See: https://developer.jamf.com/api-reference/authentication) and try again."
        case .deleteFailed:  return "Failed to remove device from Jamf Pro."
        case .deviceNotFound: return "Device not found in Jamf Pro."
        }
    }
}
