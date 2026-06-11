import SwiftUI

// MARK: - Sort Order

private enum FirmwareSortOrder: String, CaseIterable {
    case date    = "Date"
    case size    = "Size"
    case version = "Version"
}

// MARK: - InstallerView

struct InstallerView: View {
    @Environment(AppState.self) private var appState
    @Environment(CustomOSStore.self) private var customOSStore
    @Environment(InstallerStore.self) private var installerStore
    @State private var firmwares: [IPSWFirmware] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshedAt: Date? = nil
    @State private var loadedFromCache = false
    @State private var searchText: String = ""
    @State private var sortOrder: FirmwareSortOrder = .date
    @State private var isPresentingAddCustomInstaller = false
    @State private var selectedCustomInstallerForBaseVM: Installer? = nil
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]

    @State private var settings = AppSettings.load()

    // MARK: - Computed filtered lists

    private var visibleCustomInstallers: [Installer] {
        guard !searchText.isEmpty else { return installerStore.customInstallers }
        return installerStore.customInstallers.filter {
            $0.displayName.localizedStandardContains(searchText)
            || $0.description.localizedStandardContains(searchText)
            || $0.osMetadata.displayString.localizedStandardContains(searchText)
        }
    }

    private var visibleDownloadedInstallers: [Installer] {
        let base = installerStore.downloadedInstallers.filter { $0.fileExists }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedStandardContains(searchText)
            || $0.buildNumber.localizedStandardContains(searchText)
            || $0.osMetadata.displayString.localizedStandardContains(searchText)
        }
    }

    var filteredFirmwares: [IPSWFirmware] {
        let base = searchText.isEmpty ? firmwares : firmwares.filter {
            $0.displayName.localizedStandardContains(searchText)
            || $0.version.localizedStandardContains(searchText)
            || $0.buildid.localizedStandardContains(searchText)
        }
        switch sortOrder {
        case .date:    return base.sorted { $0.releasedate > $1.releasedate }
        case .size:    return base.sorted { $0.filesize > $1.filesize }
        case .version: return base.sorted { $0.version > $1.version }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading available firmwares…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                EmptyStateView("Could not load firmwares", systemImage: "exclamationmark.triangle",
                               description: err) {
                    Button("Retry") { Task { await loadFirmwares() } }
                        .buttonStyle(.borderedProminent)
                } content: { EmptyView() }
            } else {
                firmwareList
            }
        }
        .sheet(item: $selectedCustomInstallerForBaseVM,
               onDismiss: { selectedCustomInstallerForBaseVM = nil }) { installer in
            NewBaseVMSheetWithIPSW(preselectedIPSW: installer.fileURL,
                                   preselectedInstaller: installer)
        }
        .sheet(isPresented: $isPresentingAddCustomInstaller) {
            AddCustomInstallerSheet()
                .environment(installerStore)
                .environment(customOSStore)
        }
        .navigationTitle("macOS Installers")
        .searchable(text: $searchText, prompt: "Search macOS installers…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 2) {
                    Label(settings.ipswDownloadMode == .mistCli ? "mist-cli" : "ipsw.me",
                          systemImage: settings.ipswDownloadMode == .mistCli ? "terminal" : "network", )
                    .padding(8)
                    Text(settings.ipswDownloadMode == .mistCli ? "mist-cli" : "ipsw.me")
                    .font(.caption).foregroundStyle(.secondary)
                    Text(" · ")
                        .font(.caption).foregroundStyle(.secondary)
                    if let refreshed = lastRefreshedAt {
                        Text((loadedFromCache ? "Cached " : "Refreshed ") + coarseAge(of: refreshed))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(4)
                    }
                    Button { Task {
                        await IPSWService.shared.invalidateCache()
                        // Also clear mist cache
                        let mistCache = AppSettings.defaultLocalStorageRoot
                            .appendingPathComponent("mist-firmware-cache.json")
                        try? FileManager.default.removeItem(at: mistCache)
                        await loadFirmwares()
                    } } label: {
                        Label("Refresh Installers", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh installer list (⌘R)")

                }
            }

            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(FirmwareSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Sort by: \(sortOrder.rawValue)")
            }
        }
        .task { await loadFirmwares() }
    }

    // MARK: List

    private var firmwareList: some View {
        List {
            // Custom Installers section
            if !visibleCustomInstallers.isEmpty || true {
                Section {
                    ForEach(visibleCustomInstallers) { inst in
                        CustomInstallerRow(
                            installer: inst,
                            onCreateBaseVM: {
                                selectedCustomInstallerForBaseVM = inst
                            },
                            onDelete: { installerStore.delete(inst) }
                        )
                    }
                    Button {
                        isPresentingAddCustomInstaller = true
                    } label: {
                        Label("Add Custom Installer…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Custom Installers")
                }
            }

            if !visibleDownloadedInstallers.isEmpty {
                Section("Downloaded") {
                    ForEach(visibleDownloadedInstallers) { installer in
                        DownloadedInstallerRow(
                            installer: installer,
                            onCreateBaseVM: {
                                selectedCustomInstallerForBaseVM = installer
                            },
                            onDelete: {
                                installerStore.delete(installer)
                            }
                        )
                    }
                }
            }

            if !filteredFirmwares.isEmpty {
                Section("Available from Apple") {
                    ForEach(filteredFirmwares) { fw in
                        IPSWFirmwareRow(
                            firmware: fw,
                            downloadProgress: appState.activeIPSWDownloads[fw.buildid],
                            isDownloaded: installerStore.downloadedInstallers.contains(where: { installer in
                                guard let path = installer.localPath else { return false }
                                let name = (path as NSString).lastPathComponent
                                if name == fw.suggestedFilename { return true }
                                if name.contains(fw.buildid) { return true }
                                let stem = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? ""
                                let v = fw.version
                                if let r = stem.range(of: v) {
                                    let nextChar = stem[r.upperBound...].first
                                    if nextChar == nil || nextChar == "-" || nextChar == "_" { return true }
                                }
                                return false
                            }),
                            onDownload: {
                                let task = Task { await downloadFirmware(fw) }
                                downloadTasks[fw.buildid] = task
                            },
                            onCancel: {
                                downloadTasks[fw.buildid]?.cancel()
                                downloadTasks.removeValue(forKey: fw.buildid)
                                appState.activeIPSWDownloads.removeValue(forKey: fw.buildid)
                            },
                            onDelete: {
                                if let installer = installerStore.downloadedInstallers.first(where: { inst in
                                    guard let path = inst.localPath else { return false }
                                    let name = (path as NSString).lastPathComponent
                                    if name == fw.suggestedFilename { return true }
                                    if name.contains(fw.buildid) { return true }
                                    let stem = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? ""
                                    if let r = stem.range(of: fw.version) {
                                        let next = stem[r.upperBound...].first
                                        return next == nil || next == "-" || next == "_"
                                    }
                                    return false
                                }) {
                                    installerStore.delete(installer)
                                }
                            },
                            onCreateBaseVM: {
                                if let installer = installerStore.downloadedInstallers.first(where: { inst in
                                    guard let path = inst.localPath else { return false }
                                    let name = (path as NSString).lastPathComponent
                                    if name == fw.suggestedFilename { return true }
                                    if name.contains(fw.buildid) { return true }
                                    let stem = (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? ""
                                    if let r = stem.range(of: fw.version) {
                                        let next = stem[r.upperBound...].first
                                        return next == nil || next == "-" || next == "_"
                                    }
                                    return false
                                }) {
                                    selectedCustomInstallerForBaseVM = installer
                                }
                            }
                        )
                    }
                }
            } else if !isLoading {
                Section {
                    Label("No macOS firmware found. Try refreshing.", systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: Actions

    /// Human-readable age rounded to the coarsest meaningful unit (no seconds).
    private func coarseAge(of date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 120          { return "just now" }
        if secs < 3600         { return "\(secs / 60) min ago" }
        if secs < 86_400       { return "\(secs / 3600) hr ago" }
        return "\(secs / 86_400)d ago"
    }

    private func loadFirmwares() async {
        isLoading = true; errorMessage = nil
        do {
            let ipswRoot = AppSettings.load().ipswStorageRoot
            // Check cache freshness before fetching (works for both ipsw.me and mist-cli)
            let wasFresh = settings.ipswDownloadMode == .mistCli
                ? isMistCacheFresh()
                : await IPSWService.shared.isCacheFresh
            async let remoteFirmwares = fetchFirmwareList()
            firmwares = try await remoteFirmwares
            // Auto-import untracked local IPSW files
            installerStore.importUntrackedFiles(in: ipswRoot, knownFirmwares: firmwares)
            loadedFromCache = wasFresh
            lastRefreshedAt = settings.ipswDownloadMode == .mistCli
                ? mistCacheDate() ?? Date()
                : await IPSWService.shared.lastFetchDate ?? Date()
            let source = loadedFromCache ? "cache" : (settings.ipswDownloadMode == .mistCli ? "mist-cli" : "ipsw.me")
            AppLogger.shared.success(
                "Loaded \(firmwares.count) firmwares from \(source)",
                source: "InstallerView")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Check if the mist-cli disk cache is still fresh (< 24h old).
    private func isMistCacheFresh() -> Bool {
        let cacheFile = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("mist-firmware-cache.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(modified) < 86_400
    }

    private func mistCacheDate() -> Date? {
        let cacheFile = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("mist-firmware-cache.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        return modified
    }

    private func fetchFirmwareList() async throws -> [IPSWFirmware] {
        if settings.ipswDownloadMode == .mistCli {
            return try await fetchWithMistCLI()
        }
        return try await IPSWService.shared.listFirmware()
    }

    private func fetchWithMistCLI() async throws -> [IPSWFirmware] {
        // Try system mist first, then managed copy
        let managedMist = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/mist-cli").path
        let (whichOut, _) = (try? await ProcessRunner().run("/usr/bin/which", arguments: ["mist"])) ?? ("", "")
        let sysMist = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        let mistPath = !sysMist.isEmpty ? sysMist
            : FileManager.default.fileExists(atPath: managedMist) ? managedMist
            : nil
        guard let path = mistPath else {
            throw NSError(domain: "Oven", code: 0,
                userInfo: [NSLocalizedDescriptionKey:
                    "mist-cli is not installed. Switch to ipsw.me in Preferences → Build, or install mist-cli."])
        }
        let svc = MistService(runner: ProcessRunner(), mistPath: path,
                              ipswRoot: AppSettings.load().ipswStorageRoot)
        let results = try await svc.listFirmware()
        // Convert MistFirmwareInfo → IPSWFirmware for uniform display
        return results.map { mist in
            IPSWFirmware(
                identifier: "VirtualMac2,1",
                version: mist.version,
                buildid: mist.build,
                sha256sum: "",
                filesize: mist.size,
                url: mist.url ?? "",
                releasedate: mist.date,
                signed: mist.compatible
            )
        }
    }

    private func localIPSWFiles(in directory: URL) async -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return (try? FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "ipsw" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }) ?? []
    }

    private func downloadFirmware(_ fw: IPSWFirmware) async {
        let ipswRoot = AppSettings.load().ipswStorageRoot
        appState.activeIPSWDownloads[fw.buildid] = 0.0

        if settings.ipswDownloadMode == .mistCli {
            await downloadWithMistCLI(fw: fw, to: ipswRoot)
        } else {
            await downloadWithIPSWService(fw: fw, to: ipswRoot)
        }
    }

    private func downloadWithIPSWService(fw: IPSWFirmware, to directory: URL) async {
        AppLogger.shared.log("Downloading \(fw.displayName) (\(fw.formattedSize))…", source: "InstallerView")
        for await event in await IPSWService.shared.download(fw, to: directory) {
            switch event {
            case .progress(let fraction, _, _):
                appState.activeIPSWDownloads[fw.buildid] = fraction
            case .completed(let url):
                appState.activeIPSWDownloads.removeValue(forKey: fw.buildid)
                installerStore.recordDownload(firmware: fw, localURL: url)
                AppLogger.shared.success("Downloaded: \(url.lastPathComponent)", source: "InstallerView")
            case .failed(let error):
                appState.activeIPSWDownloads.removeValue(forKey: fw.buildid)
                errorMessage = "Download failed: \(error.localizedDescription)"
                AppLogger.shared.error(error.localizedDescription, source: "InstallerView")
            }
        }
    }

    private func downloadWithMistCLI(fw: IPSWFirmware, to directory: URL) async {
        let managedMist = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/mist-cli").path
        let (whichOut, _) = (try? await ProcessRunner().run("/usr/bin/which", arguments: ["mist"])) ?? ("", "")
        let sysMist = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        let mistPath = !sysMist.isEmpty ? sysMist
            : FileManager.default.fileExists(atPath: managedMist) ? managedMist : nil
        guard let path = mistPath else {
            errorMessage = "mist-cli not found. Switch to ipsw.me in Preferences → Build."
            return
        }
        let svc = MistService(runner: ProcessRunner(), mistPath: path, ipswRoot: directory)
        let stream = await svc.downloadFirmware(version: fw.version, build: fw.buildid)
        for await event in stream {
            switch event {
            case .stdout(let line):
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasSuffix("%"), let pct = Double(t.dropLast().trimmingCharacters(in: .whitespaces)) {
                    appState.activeIPSWDownloads[fw.buildid] = min(pct / 100.0, 1.0)
                }
            case .exit(let code):
                appState.activeIPSWDownloads.removeValue(forKey: fw.buildid)
                if code == 0 {
                    // Find the downloaded file in the directory and record it
                    let localFiles = await localIPSWFiles(in: directory)
                    if let foundURL = localFiles.first(where: { url in
                        let name = url.lastPathComponent
                        if name == fw.suggestedFilename { return true }
                        if name.contains(fw.buildid) { return true }
                        let stem = url.deletingPathExtension().lastPathComponent
                        if let r = stem.range(of: fw.version) {
                            let next = stem[r.upperBound...].first
                            return next == nil || next == "-" || next == "_"
                        }
                        return false
                    }) {
                        installerStore.recordDownload(firmware: fw, localURL: foundURL)
                    }
                    AppLogger.shared.success("Downloaded: \(fw.displayName)", source: "InstallerView")
                } else {
                    errorMessage = "mist-cli download failed for \(fw.displayName)"
                }
            default: break
            }
        }
    }
}

// MARK: - Firmware row (Available from Apple)

struct IPSWFirmwareRow: View {
    let firmware: IPSWFirmware
    let downloadProgress: Double?
    let isDownloaded: Bool
    let onDownload: () -> Void
    var onCancel: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onCreateBaseVM: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var isPresentingDeleteConfirm = false

    private var formattedReleaseDate: String {
        let raw = String(firmware.releasedate.prefix(10)) // "YYYY-MM-DD"
        if let date = Self.releaseDateParser.date(from: raw) {
            return Self.releaseDateFormatter.string(from: date)
        }
        return raw
    }

    private static let releaseDateParser: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let releaseDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Expanded detail rows
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Label {
                        Text("Build").foregroundStyle(.secondary) +
                        Text("  ") +
                        Text(firmware.buildid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "hammer")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    Label {
                        Text("Released").foregroundStyle(.secondary) +
                        Text("  ") +
                        Text(formattedReleaseDate).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                if firmware.signed {
                    Label("Currently signed by Apple — eligible for installation", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if isDownloaded, let onCreateBaseVM {
                    Button(action: onCreateBaseVM) {
                        Label("Create Base VM", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 40)
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 12) {
                // Icon with optional downloaded badge
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "apple.logo")
                        .font(.title3)
                        .foregroundStyle(isDownloaded ? .green : .secondary)
                        .frame(width: 28, height: 28)
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, .green)
                            .offset(x: 4, y: 4)
                    }
                }
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(firmware.displayName).fontWeight(.medium)
                        // Build number in monospace chip
                        Text(firmware.buildid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.chip))
                        if firmware.signed {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2).foregroundStyle(.green)
                                .help("Currently signed by Apple")
                        }
                    }
                    // Size + date
                    Text("\(firmware.formattedSize) · \(formattedReleaseDate)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                // Right-side: download progress, status pill, or download button
                Group {
                    if let progress = downloadProgress {
                        VStack(alignment: .trailing, spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 100)
                            HStack(spacing: 6) {
                                Text("\(Int(progress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let onCancel {
                                    Button("Cancel", action: onCancel)
                                        .buttonStyle(.bordered).controlSize(.mini)
                                }
                            }
                        }
                    } else if isDownloaded {
                        HStack(spacing: 6) {
                            // "Ready to use" status pill
                            Text("Ready to use")
                                .font(.caption2).fontWeight(.medium)
                                .foregroundStyle(.green)
                                .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
                                .background(Color.green.opacity(0.12),
                                            in: Capsule())
                                .overlay { Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1) }

                            if let onDelete {
                                Button(role: .destructive,
                                       action: { isPresentingDeleteConfirm = true }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                .help("Delete IPSW file")
                                .confirmationDialog(
                                    "Delete \"\(firmware.displayName)\"?",
                                    isPresented: $isPresentingDeleteConfirm,
                                    titleVisibility: .visible
                                ) {
                                    Button("Delete", role: .destructive, action: onDelete)
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("This will permanently delete the IPSW file from disk.")
                                }
                            }
                        }
                    } else {
                        Button(action: onDownload) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .help("Download \(firmware.formattedSize) IPSW installer")
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .contextMenu {
            if isDownloaded {
                if let onCreateBaseVM {
                    Button { onCreateBaseVM() } label: {
                        Label("Create Base VM", systemImage: "plus.circle.fill")
                    }
                }
                Divider()
                if let onDelete {
                    Button(role: .destructive) { isPresentingDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } else if downloadProgress == nil {
                Button { onDownload() } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}

// MARK: - Downloaded Installer Row

struct DownloadedInstallerRow: View {
    let installer: Installer
    let onCreateBaseVM: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isPresentingDeleteConfirm = false

    private var formattedFileSize: String? {
        if let bytes = installer.sizeBytes {
            let gb = Double(bytes) / 1_073_741_824
            return String(format: "%.2f GB", gb)
        }
        guard let url = installer.fileURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        let gb = Double(size) / 1_073_741_824
        return gb.formatted(.number.precision(.fractionLength(2))) + " GB"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Drive icon with green checkmark badge
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "internaldrive.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .green)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(installer.displayName).fontWeight(.medium)
                HStack(spacing: 8) {
                    // Prominent file size
                    if let size = formattedFileSize {
                        Text(size)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    // Build number if present
                    if !installer.buildNumber.isEmpty {
                        Text(installer.buildNumber)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    // "Ready to use" status pill
                    Text("Ready to use")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(.green)
                        .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .overlay { Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1) }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onCreateBaseVM) {
                    Label("Create Base VM", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)

                if let onDelete {
                    Button(role: .destructive, action: { isPresentingDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Delete IPSW file")
                    .confirmationDialog(
                        "Delete \"\(installer.displayName)\"?",
                        isPresented: $isPresentingDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive, action: onDelete)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete the IPSW file from disk.")
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .contextMenu {
            Button { onCreateBaseVM() } label: {
                Label("Create Base VM", systemImage: "plus.circle.fill")
            }
            if let url = installer.fileURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            Divider()
            if let onDelete {
                Button(role: .destructive) { isPresentingDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Custom Installer Row

private struct CustomInstallerRow: View {
    let installer: Installer
    let onCreateBaseVM: () -> Void
    let onDelete: () -> Void

    @State private var isPresentingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: installer.fileExists ? "doc.zipper" : "externaldrive.fill.trianglebadge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(installer.fileExists ? .blue : .orange)
                    .frame(width: 28, height: 28)
                if installer.osMetadata.isBeta {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, .orange)
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(installer.displayName).fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(installer.osMetadata.displayString)
                        .font(.caption).foregroundStyle(.secondary)
                    if !installer.description.isEmpty {
                        Text(installer.description)
                            .font(.caption).foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if !installer.fileExists {
                        Text("File not found")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    } else if installer.isManagedCopy {
                        Text("Managed")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if installer.fileExists {
                    Button(action: onCreateBaseVM) {
                        Label("Create Base VM", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Button(role: .destructive, action: { isPresentingDeleteConfirm = true }) {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help(installer.isManagedCopy ? "Delete IPSW and remove from library" : "Remove from library")
                .confirmationDialog(
                    "Remove \"\(installer.displayName)\"?",
                    isPresented: $isPresentingDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(installer.isManagedCopy
                         ? "This will also delete the IPSW file from Oven's storage."
                         : "The IPSW file will not be deleted from disk.")
                }
            }
        }
        .padding(.vertical, 6)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .contextMenu {
            if installer.fileExists {
                Button { onCreateBaseVM() } label: {
                    Label("Create Base VM", systemImage: "plus.circle.fill")
                }
                if let url = installer.fileURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
                Divider()
            }
            Button(role: .destructive) { isPresentingDeleteConfirm = true } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: - NewBaseVMSheetWithIPSW (bridge)
// Passes the real app-wide BaseVMStore through the environment so that VMs
// created here appear immediately in the Base VMs list.

struct NewBaseVMSheetWithIPSW: View {
    let preselectedIPSW: URL?
    var preselectedInstaller: Installer? = nil

    var body: some View {
        // Environment objects (BaseVMStore, AppTheme, PackerTemplateStore, BuildingBlockStore)
        // are already injected by the presenting view via the app-level environment chain.
        NewBaseVMSheet(preselectedIPSWURL: preselectedIPSW,
                       preselectedInstaller: preselectedInstaller)
    }
}
