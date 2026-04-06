import Foundation
import Security
import LocalAuthentication

// MARK: - KeychainService
// Simple wrapper for storing and retrieving string secrets by key.
// Used for registry passwords, MDM server API passwords, and base VM credentials.

enum KeychainService {

    private static let service = "com.hooleahn.oven"

    // MARK: - Store

    @discardableResult
    static func store(key: String, value: String) -> Bool {
        let data = value.data(using: .utf8)!
        delete(key: key) // Remove existing entry first

        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlocked,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Retrieve

    static func retrieve(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Sensitive store (requires device passcode / biometrics)

    /// Stores a value with `userPresence` access control — the user must authenticate
    /// with Touch ID or device passcode before the item can be read.
    /// Use for MDM API passwords and registry tokens.
    @discardableResult
    static func storeSensitive(key: String, value: String) -> Bool {
        let data = value.data(using: .utf8)!
        deleteSensitive(key: key)

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .userPresence,
            &error
        ) else { return false }

        let query: [CFString: Any] = [
            kSecClass:             kSecClassGenericPassword,
            kSecAttrService:       service + ".sensitive",
            kSecAttrAccount:       key,
            kSecValueData:         data,
            kSecAttrAccessControl: access,
            kSecUseAuthenticationContext: sessionContext,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Shared auth context — evaluated once per session so the user only
    /// sees one Touch ID prompt regardless of how many credentials are accessed.
    private static var _sessionContext: LAContext?
    static var sessionContext: LAContext {
        if let ctx = _sessionContext, !ctx.isCredentialSet(.applicationPassword) == false {
            return ctx
        }
        let ctx = LAContext()
        ctx.localizedReason = "access your stored credentials"
        ctx.touchIDAuthenticationAllowableReuseDuration = 30  // reuse auth for 30s
        _sessionContext = ctx
        return ctx
    }

    static func invalidateSessionContext() {
        _sessionContext?.invalidate()
        _sessionContext = nil
    }

    static func retrieveSensitive(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service + ".sensitive",
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
            kSecUseAuthenticationContext: sessionContext,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    @discardableResult
    static func deleteSensitive(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service + ".sensitive",
            kSecAttrAccount: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Delete

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
