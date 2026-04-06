import Foundation

// MARK: - RegistryCredential
// Per-registry auth config. Password stored in Keychain.
// tart uses: tart login <registry> with env vars TART_REGISTRY_USERNAME / PASSWORD

struct RegistryCredential: Identifiable, Codable, Hashable , Sendable {
    let id: UUID
    var registry: String     // e.g. "ghcr.io", "docker.io", "registry.example.com"
    var username: String
    // Password in Keychain keyed by id.uuidString

    var keychainKey: String { "\(id.uuidString).registryPassword" }

    var password: String? {
        get { KeychainService.retrieve(key: keychainKey) }
        nonmutating set {
            if let v = newValue { KeychainService.store(key: keychainKey, value: v) }
            else { KeychainService.delete(key: keychainKey) }
        }
    }
}
