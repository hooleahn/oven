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

    func load() {
        credentials = AppDatabase.shared.readOrDefault(.registryCredentials, default: [])
        images      = AppDatabase.shared.readOrDefault(.registryImages, default: [])
        // isPulled is authoritative from syncFromTart (tart list --source oci).
        // Load the last-known cached state; syncFromTart will correct it.
    }

    func saveImages() {
        AppDatabase.shared.writeSilently(images, to: .registryImages)
    }

    func saveCredentials() {
        AppDatabase.shared.writeSilently(credentials, to: .registryCredentials)
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
        let firstComp = trimmed.components(separatedBy: "/").first ?? ""
        let host = (firstComp.contains(".") || firstComp.contains(":") || firstComp == "localhost")
            ? firstComp : selectedRegistry
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

    /// Sync OCI image state from `tart list --source oci`.
    ///
    /// `isPulled` is determined solely by whether tart has the imageRef in its OCI cache.
    /// Manually-added images that aren't in the cache are always unpulled.
    /// Images in the cache that Oven doesn't track yet are auto-discovered.
    func syncFromTart(tartPath: String) async {
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartPath)
        guard let ociVMs = try? await tartSvc.listOCI() else { return }

        let ociNames = Set(ociVMs.filter { !$0.name.contains("@sha256:") }.map { $0.name })
        var changed = false

        // tart's OCI cache is the sole source of truth for isPulled
        for i in images.indices {
            let newPulled = ociNames.contains(images[i].imageRef)
            if images[i].isPulled != newPulled {
                images[i].isPulled = newPulled
                changed = true
            }
        }

        // Auto-discover OCI images tart has that Oven isn't tracking yet
        for info in ociVMs {
            guard !info.name.contains("@sha256:") else { continue }
            guard !images.contains(where: { $0.imageRef == info.name }) else { continue }
            let firstComp = info.name.components(separatedBy: "/").first ?? ""
            let host = (firstComp.contains(".") || firstComp.contains(":") || firstComp == "localhost")
                ? firstComp : "ghcr.io"
            images.append(RegistryImage(id: UUID(), registry: host, imageRef: info.name,
                                        isPulled: true, localName: nil, pulledAt: nil, sizeBytes: nil))
            changed = true
        }

        if changed { saveImages() }
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
        else                               { osName = .unknown }

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
