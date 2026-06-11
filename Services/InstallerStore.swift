import Foundation

@MainActor
@Observable
final class InstallerStore {

    var installers: [Installer] = []
    var isCopying = false
    var copyError: String?

    var customInstallers: [Installer] { installers.filter { $0.type == .custom } }
    var downloadedInstallers: [Installer] { installers.filter { $0.type == .downloaded } }

    init() { load() }

    // MARK: - Persistence

    func load() {
        var records = AppDatabase.shared.readOrDefault(.installers, default: [Installer]())

        // One-time migration: import old CustomInstaller records
        let legacy = AppDatabase.shared.readOrDefault(.customInstallers, default: [CustomInstaller]())
        if !legacy.isEmpty {
            let migrated = legacy.compactMap { old -> Installer? in
                guard !records.contains(where: { $0.id == old.id }) else { return nil }
                return Installer(migrating: old)
            }
            records.append(contentsOf: migrated)
            AppDatabase.shared.writeSilently(records, to: .installers)
            AppDatabase.shared.writeSilently([CustomInstaller](), to: .customInstallers)
        }
        installers = records
    }

    private func save() {
        AppDatabase.shared.writeSilently(installers, to: .installers)
    }

    // MARK: - Mutations

    func add(_ installer: Installer) {
        installers.append(installer)
        save()
    }

    func delete(_ installer: Installer) {
        if installer.isManagedCopy, let url = installer.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        installers.removeAll { $0.id == installer.id }
        save()
    }

    func update(_ installer: Installer) {
        guard let idx = installers.firstIndex(where: { $0.id == installer.id }) else { return }
        installers[idx] = installer
        save()
    }

    func markLastBuildDate(for installerID: UUID) {
        guard let idx = installers.firstIndex(where: { $0.id == installerID }) else { return }
        installers[idx].lastBuildDate = Date()
        save()
    }

    // MARK: - Download completion

    /// Call when an ipsw.me firmware download finishes. Creates or updates a .downloaded record.
    func recordDownload(firmware: IPSWFirmware, localURL: URL) {
        // Avoid duplicates — update if already tracked (e.g. re-downloaded)
        if let idx = installers.firstIndex(where: {
            $0.type == .downloaded && ($0.buildNumber == firmware.buildid || $0.localPath == localURL.path)
        }) {
            installers[idx].localPath = localURL.path
            installers[idx].downloadDate = Date()
            save()
            return
        }
        let relDate: Date? = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: firmware.releasedate)
                ?? ISO8601DateFormatter().date(from: firmware.releasedate)
        }()
        let installer = Installer(
            osMetadata: OSMetadata(from: firmware),
            buildNumber: firmware.buildid,
            releaseDate: relDate,
            sizeBytes: Int(firmware.filesize),
            sha256: firmware.sha256sum,
            downloadURL: URL(string: firmware.url),
            localPath: localURL.path,
            downloadDate: Date(),
            type: .downloaded
        )
        add(installer)
    }

    // MARK: - Custom installer registration

    func existingCustomInstaller(for metadata: OSMetadata) -> Installer? {
        customInstallers.first { inst in
            inst.osMetadata.osName == metadata.osName
            && inst.osMetadata.osVersion == metadata.osVersion
            && inst.osMetadata.customMajorVersion == metadata.customMajorVersion
            && inst.osMetadata.customReleaseName == metadata.customReleaseName
        }
    }

    func register(
        osMetadata: OSMetadata,
        buildNumber: String = "",
        description: String = "",
        sourceURL: URL,
        copyToStorage: Bool
    ) async {
        guard !isCopying else { return }

        var localPath = sourceURL.path
        var isManagedCopy = false

        if copyToStorage {
            isCopying = true
            copyError = nil
            let ipswRoot = AppSettings.load().ipswStorageRoot
            let destName: String = {
                let betaSuffix = osMetadata.isBeta
                    ? (osMetadata.betaLabel.isEmpty ? "-beta" : "-\(osMetadata.betaLabel.replacingOccurrences(of: " ", with: "-"))")
                    : ""
                let releaseName: String = {
                    switch osMetadata.osName {
                    case .custom: return osMetadata.customReleaseName.isEmpty ? "Custom" : osMetadata.customReleaseName
                    default: return osMetadata.osName.rawValue
                    }
                }()
                let vers = osMetadata.osVersion.isEmpty ? osMetadata.customMajorVersion : osMetadata.osVersion
                let build = buildNumber.isEmpty ? "" : "-\(buildNumber)"
                let versionPart = vers.isEmpty ? "" : "-\(vers)"
                return "macOS-\(releaseName)\(versionPart)\(betaSuffix)\(build).ipsw"
            }()
            let destURL = ipswRoot.appendingPathComponent(destName)
            do {
                try FileManager.default.createDirectory(at: ipswRoot, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try await Task.detached(priority: .userInitiated) {
                        try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    }.value
                }
                localPath = destURL.path
                isManagedCopy = true
            } catch {
                copyError = error.localizedDescription
                AppLogger.shared.error("Failed to copy IPSW: \(error.localizedDescription)", source: "InstallerStore")
            }
            isCopying = false
        }

        let installer = Installer(
            osMetadata: osMetadata,
            buildNumber: buildNumber,
            localPath: localPath,
            description: description,
            type: .custom,
            isManagedCopy: isManagedCopy
        )
        add(installer)
    }

    // MARK: - Discovery of untracked local files

    /// Scan `directory` for .ipsw files not already tracked, and add them as .downloaded records.
    /// Called on InstallerView appear to import files downloaded outside the app.
    func importUntrackedFiles(in directory: URL, knownFirmwares: [IPSWFirmware] = []) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ).filter({ $0.pathExtension.lowercased() == "ipsw" }) else { return }

        for url in files {
            // Skip already-tracked files
            if installers.contains(where: { $0.localPath == url.path }) { continue }

            // Try to match against known firmwares first (best metadata)
            if let fw = knownFirmwares.first(where: { fw in
                let name = url.lastPathComponent
                return name == fw.suggestedFilename || name.contains(fw.buildid)
            }) {
                recordDownload(firmware: fw, localURL: url)
                continue
            }

            // Fall back: infer from filename
            let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let meta = OSMetadata.detect(from: url.lastPathComponent) ?? OSMetadata()
            let installer = Installer(
                osMetadata: meta,
                sizeBytes: resources?.fileSize,
                localPath: url.path,
                downloadDate: resources?.creationDate,
                type: .downloaded
            )
            add(installer)
        }
    }
}
