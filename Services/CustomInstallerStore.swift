import Foundation

@MainActor
@Observable
final class CustomInstallerStore {

    var installers: [CustomInstaller] = []
    var isCopying = false
    var copyError: String?

    init() { load() }

    func load() {
        installers = AppDatabase.shared.readOrDefault(.customInstallers, default: [])
    }

    func add(_ installer: CustomInstaller) {
        installers.append(installer)
        save()
    }

    func delete(_ installer: CustomInstaller) {
        if installer.isManagedCopy {
            try? FileManager.default.removeItem(at: installer.fileURL)
        }
        installers.removeAll { $0.id == installer.id }
        save()
    }

    /// Register a local .ipsw, optionally copying it into Oven's managed IPSW storage first.
    func register(
        displayName: String,
        osName: MacOSRelease.Name,
        customOSReleaseName: String = "",
        customOSMajorVersion: String = "",
        osVersion: String,
        isBeta: Bool,
        betaLabel: String,
        sourceURL: URL,
        copyToStorage: Bool
    ) async {
        var localPath = sourceURL.path
        var isManagedCopy = false

        if copyToStorage {
            isCopying = true
            copyError = nil
            let ipswRoot = AppSettings.load().ipswStorageRoot
            let destURL = ipswRoot.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                try FileManager.default.createDirectory(
                    at: ipswRoot, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
                localPath = destURL.path
                isManagedCopy = true
            } catch {
                copyError = error.localizedDescription
                AppLogger.shared.error(
                    "Failed to copy IPSW: \(error.localizedDescription)",
                    source: "CustomInstallerStore")
            }
            isCopying = false
        }

        let installer = CustomInstaller(
            displayName: displayName,
            osName: osName,
            customOSReleaseName: customOSReleaseName,
            customOSMajorVersion: customOSMajorVersion,
            osVersion: osVersion,
            isBeta: isBeta,
            betaLabel: betaLabel,
            localPath: localPath,
            isManagedCopy: isManagedCopy
        )
        add(installer)
    }

    private func save() {
        AppDatabase.shared.writeSilently(installers, to: .customInstallers)
    }
}
