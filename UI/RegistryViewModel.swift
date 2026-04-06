import SwiftUI

// MARK: - RegistryViewModel

@MainActor
@Observable
final class RegistryViewModel {

    var images: [RegistryImage] = []
    var selectedRegistry = "ghcr.io"
    var newImageRef = ""
    var errorMessage: String?
    var credentials: [RegistryCredential] = []
    var pendingPull: RegistryImage?
    var pendingPullIsBase: Bool?
    var pendingPullUsername: String = ""   // set by PullDestinationSheet
    var pendingPullPassword: String = ""   // stored in Keychain after pull
    var showCirrusCatalogue = false

    // MARK: - Persistence URLs

    private var imagesURL: URL {
        AppSettings.defaultLocalStorageRoot.appendingPathComponent("registry-images.json")
    }

    private var credentialsURL: URL {
        AppSettings.defaultLocalStorageRoot.appendingPathComponent("registry-credentials.json")
    }

    // MARK: - Filtered list

    func filteredImages(searchQuery: String) -> [RegistryImage] {
        guard !searchQuery.isEmpty else { return images }
        return images.filter { $0.imageRef.localizedCaseInsensitiveContains(searchQuery) }
    }

    // MARK: - Load / save

    func load(vmStore: VMStore, baseVMStore: BaseVMStore) {
        credentials = AppDatabase.shared.readOrDefault(.registryCredentials, default: [])
        images      = AppDatabase.shared.readOrDefault(.registryImages, default: [])
        if !images.isEmpty { reconcileIsPulled(vmStore: vmStore, baseVMStore: baseVMStore) }
    }

    func saveImages() {
        AppDatabase.shared.writeSilently(images, to: .registryImages)
    }

    func saveCredentials() {
        AppDatabase.shared.writeSilently(credentials, to: .registryCredentials)
    }

    // MARK: - Reconcile pulled state

    func reconcileIsPulled(vmStore: VMStore, baseVMStore: BaseVMStore) {
        let allNames = Set(vmStore.vms.map { $0.name })
            .union(Set(baseVMStore.baseVMs.map { $0.name }))
        for i in images.indices {
            let img = images[i]
            let expectedLocal = img.localName ?? img.imageRef
                .components(separatedBy: "/").last?
                .replacingOccurrences(of: ":", with: "-")
            let expectedBase = expectedLocal.map { "base-\($0)" }
            let byRef = vmStore.vms.contains { $0.registryImageRef == img.imageRef }
                || baseVMStore.baseVMs.contains { $0.registryImageRef == img.imageRef }
            let byName = [expectedLocal, expectedBase].compactMap { $0 }
                .contains(where: { allNames.contains($0) })
            images[i].isPulled = byRef || byName || img.isPulled
        }
    }

    // MARK: - Image management

    func addCirrusImage(_ img: CirrusLabsImage) {
        guard !images.contains(where: { $0.imageRef == img.imageRef }) else { return }
        let regImage = img.registryImage
        images.append(regImage)
        saveImages()
        pendingPull = regImage
    }

    func addManualImage(ref: String) {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !images.contains(where: { $0.imageRef == trimmed }) else { return }
        let host = trimmed.components(separatedBy: "/").first ?? selectedRegistry
        let img = RegistryImage(id: UUID(), registry: host, imageRef: trimmed,
                                isPulled: false, localName: nil, pulledAt: nil, sizeBytes: nil)
        images.append(img)
        saveImages()
        newImageRef = ""
    }

    func removeImage(_ img: RegistryImage) {
        images.removeAll { $0.id == img.id }
        saveImages()
    }

    /// Auto-discover OCI images from `tart list --source oci` and add any
    /// not already tracked. Never removes images the user added manually.
    func syncFromTart(tartPath: String, vmStore: VMStore, baseVMStore: BaseVMStore) async {
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartPath)
        guard let ociVMs = try? await tartSvc.listOCI() else { return }

        var changed = false
        for info in ociVMs {
            // Skip @sha256 digest variants — only track the tag refs
            guard !info.name.contains("@sha256:") else { continue }
            guard !images.contains(where: { $0.imageRef == info.name }) else { continue }
            let host = info.name.components(separatedBy: "/").first ?? "ghcr.io"
            let img = RegistryImage(id: UUID(), registry: host, imageRef: info.name,
                                    isPulled: true, localName: nil,
                                    pulledAt: nil, sizeBytes: nil)
            images.append(img)
            changed = true
        }
        if changed {
            reconcileIsPulled(vmStore: vmStore, baseVMStore: baseVMStore)
            saveImages()
        }
    }

    // MARK: - OS inference

    func inferOSFromRef(_ ref: String) -> (MacOSRelease.Name, String) {
        let lower = ref.lowercased()
        let osName: MacOSRelease.Name
        if lower.contains("tahoe")         { osName = .tahoe }
        else if lower.contains("sequoia")  { osName = .sequoia }
        else if lower.contains("sonoma")   { osName = .sonoma }
        else if lower.contains("ventura")  { osName = .ventura }
        else if lower.contains("monterey") { osName = .monterey }
        else                               { osName = .sequoia }

        let tag = ref.components(separatedBy: ":").last ?? "latest"
        let version = tag == "latest" ? "" : tag
        return (osName, version)
    }

    // MARK: - Registry service

    func makeRegistryService(tartPath: String) -> RegistryService? {
        guard FileManager.default.fileExists(atPath: tartPath) else { return nil }
        return RegistryService(runner: ProcessRunner(), tartPath: tartPath)
    }
}
