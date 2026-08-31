import Foundation

// MARK: - WebhookAuthType

enum WebhookAuthType: String, Codable, CaseIterable {
    case none   = "none"
    case basic  = "basic"
    case custom = "custom"

    var label: String {
        switch self {
        case .none:   return "None"
        case .basic:  return "Basic"
        case .custom: return "Custom"
        }
    }
}

// MARK: - WebhookNotification

struct WebhookNotification: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var url: String
    var isEnabled: Bool
    var authType: WebhookAuthType
    // Basic auth: password stored separately in Keychain
    var basicAuthUsername: String
    // Custom auth: header value stored separately in Keychain
    var customAuthHeaderName: String
    // "Header-Name: Value" one per line
    var additionalHeaders: String
    // Template with %%VMNAME%%, %%EVENTTYPE%%, %%TIMESTAMP%%, %%DATETIME%% tokens
    var jsonPayload: String
    // macOS date(1) format specifiers; empty = ISO 8601
    var datetimeFormat: String
    // NotificationEvent.rawValue entries this webhook fires for
    var enabledEvents: [String]

    init(
        id: UUID = UUID(),
        displayName: String = "",
        url: String = "",
        isEnabled: Bool = true,
        authType: WebhookAuthType = .none,
        basicAuthUsername: String = "",
        customAuthHeaderName: String = "",
        additionalHeaders: String = "",
        jsonPayload: String = WebhookNotification.defaultPayload,
        datetimeFormat: String = "",
        enabledEvents: [String] = NotificationEvent.allCases.map(\.rawValue)
    ) {
        self.id = id
        self.displayName = displayName
        self.url = url
        self.isEnabled = isEnabled
        self.authType = authType
        self.basicAuthUsername = basicAuthUsername
        self.customAuthHeaderName = customAuthHeaderName
        self.additionalHeaders = additionalHeaders
        self.jsonPayload = jsonPayload
        self.datetimeFormat = datetimeFormat
        self.enabledEvents = enabledEvents
    }

    // Lenient decode: every field falls back to its default when absent, so
    // adding a field to this model never invalidates webhooks saved by an
    // older build (a strict synthesized decode would drop the whole array).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName          = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        url                  = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        isEnabled            = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        authType             = try c.decodeIfPresent(WebhookAuthType.self, forKey: .authType) ?? .none
        basicAuthUsername    = try c.decodeIfPresent(String.self, forKey: .basicAuthUsername) ?? ""
        customAuthHeaderName = try c.decodeIfPresent(String.self, forKey: .customAuthHeaderName) ?? ""
        additionalHeaders    = try c.decodeIfPresent(String.self, forKey: .additionalHeaders) ?? ""
        jsonPayload          = try c.decodeIfPresent(String.self, forKey: .jsonPayload) ?? WebhookNotification.defaultPayload
        datetimeFormat       = try c.decodeIfPresent(String.self, forKey: .datetimeFormat) ?? ""
        enabledEvents        = try c.decodeIfPresent([String].self, forKey: .enabledEvents)
            ?? NotificationEvent.allCases.map(\.rawValue)
    }

    static let defaultPayload = """
{
  "event": "%%EVENTTYPE%%",
  "vm": "%%VMNAME%%",
  "timestamp": %%TIMESTAMP%%,
  "datetime": "%%DATETIME%%"
}
"""
}
