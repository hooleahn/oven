import SwiftUI

// MARK: - InstallerView

struct InstallerView: View {
    @EnvironmentObject var appState: AppState
    @State private var firmwares: [IPSWFirmware] = []
    @State private var localIPSWs: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshedAt: Date? = nil
    @State private var loadedFromCache = false
    @State private var searchText: String = ""
    @State private var isPresentingBaseVMSheet = false
    @State private var selectedIPSWForBaseVM: URL? = nil

    private var settings: AppSettings { AppSettings.load() }

    var filteredLocalIPSWs: [URL] {
        guard !searchText.isEmpty else { return localIPSWs }
        let q = searchText.lowercased()
        return localIPSWs.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(q) }
    }

    var filteredFirmwares: [IPSWFirmware] {
        guard !searchText.isEmpty else { return firmwares }
        let q = searchText.lowercased()
        return firmwares.filter {
            $0.displayName.lowercased().contains(q) || $0.version.contains(q) || $0.buildid.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView("Loading available firmwares…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                EmptyStateView("Could not load firmwares", systemImage: "exclamationmark.triangle",
                               description: err) {
                    Button("Retry") { Task { await loadFirmwares() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                firmwareList
            }
        }
        .navigationTitle("macOS Installers")
        .searchable(text: $searchText, prompt: "Search macOS installers…")
        .task { await loadFirmwares() }
        .sheet(isPresented: $isPresentingBaseVMSheet) {
            NewBaseVMSheetWithIPSW(preselectedIPSW: selectedIPSWForBaseVM)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()

            // Show which source is active
            if let refreshed = lastRefreshedAt {
                Text((loadedFromCache ? "Cached · " : "Refreshed · ") + coarseAge(of: refreshed))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label(settings.ipswDownloadMode == .mistCli ? "mist-cli" : "ipsw.me",
                  systemImage: settings.ipswDownloadMode == .mistCli ? "terminal" : "network")
                .font(.caption).foregroundStyle(.secondary)

            Button { Task {
                    await IPSWService.shared.invalidateCache()
                    // Also clear mist cache
                    let mistCache = AppSettings.defaultLocalStorageRoot
                        .appendingPathComponent("mist-firmware-cache.json")
                    try? FileManager.default.removeItem(at: mistCache)
                    await loadFirmwares()
                } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh firmware list")
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    // MARK: List

    private var firmwareList: some View {
        List {
            if !filteredLocalIPSWs.isEmpty {
                Section("Downloaded") {
                    ForEach(filteredLocalIPSWs, id: \.path) { url in
                        LocalIPSWRow(url: url, onCreateBaseVM: {
                            selectedIPSWForBaseVM = url
                            isPresentingBaseVMSheet = true
                        }, onDelete: {
                            try? FileManager.default.removeItem(at: url)
                            localIPSWs.removeAll { $0 == url }
                        })
                    }
                }
            }

            if !filteredFirmwares.isEmpty {
                Section("Available from Apple") {
                    ForEach(filteredFirmwares) { fw in
                        IPSWFirmwareRow(
                            firmware: fw,
                            downloadProgress: appState.activeIPSWDownloads[fw.buildid],
                            isDownloaded: localIPSWs.contains(where: {
                                let name = $0.lastPathComponent
                                // 1. Exact Apple filename (downloaded via ipsw.me)
                                if name == fw.suggestedFilename { return true }
                                // 2. Buildid match (unique per release, present in Apple filenames)
                                if name.contains(fw.buildid) { return true }
                                // 3. Version match — the character immediately after the version
                                //    string must NOT be a digit OR a dot (which would indicate
                                //    another version component, e.g. "15.6" must not match "15.6.1").
                                //    Handles mist-cli naming: "macOS-15.6.1.ipsw" → version "15.6.1"
                                //    is followed by "." then end-of-stem, so we check the full stem.
                                // Strip extension so "macOS-15.6.1.ipsw" → "macOS-15.6.1"
                                // Then "15.6.1" ends at nil (match), "15.6" is followed by ".1" (reject)
                                let stem = ($0.deletingPathExtension()).lastPathComponent
                                let v = fw.version
                                if let r = stem.range(of: v) {
                                    let nextChar = stem[r.upperBound...].first
                                    if nextChar == nil || nextChar == "-" || nextChar == "_" { return true }
                                }
                                return false
                            }),
                            onDownload: { Task { await downloadFirmware(fw) } },
                            onDelete: {
                                if let url = localIPSWs.first(where: { u in
                                    let name = u.lastPathComponent
                                    if name == fw.suggestedFilename { return true }
                                    if name.contains(fw.buildid) { return true }
                                    let stem = u.deletingPathExtension().lastPathComponent
                                    if let r = stem.range(of: fw.version) {
                                        let next = stem[r.upperBound...].first
                                        return next == nil || next == "-" || next == "_"
                                    }
                                    return false
                                }) {
                                    try? FileManager.default.removeItem(at: url)
                                    localIPSWs.removeAll { $0 == url }
                                }
                            }
                        )
                    }
                }
            } else if !isLoading {
                Section {
                    EmptyStateView("No Firmwares", systemImage: "arrow.down.circle",
                                   description: "No macOS firmware found. Try refreshing.")
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
            async let localFiles = localIPSWFiles(in: ipswRoot)
            firmwares  = try await remoteFirmwares
            localIPSWs = await localFiles
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
                localIPSWs = await localIPSWFiles(in: directory)
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
                    localIPSWs = await localIPSWFiles(in: directory)
                    AppLogger.shared.success("Downloaded: \(fw.displayName)", source: "InstallerView")
                } else {
                    errorMessage = "mist-cli download failed for \(fw.displayName)"
                }
            default: break
            }
        }
    }
}

// MARK: - Firmware row (unified for both sources)

struct IPSWFirmwareRow: View {
    let firmware: IPSWFirmware
    let downloadProgress: Double?
    let isDownloaded: Bool
    let onDownload: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isPresentingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDownloaded ? "internaldrive.fill" : "apple.logo")
                .font(.title3)
                .foregroundStyle(isDownloaded ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(firmware.displayName).fontWeight(.medium)
                    Text(firmware.buildid)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    if firmware.signed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                            .help("Currently signed by Apple")
                    }
                }
                Text("\(firmware.formattedSize) · Released on \(firmware.releasedate.prefix(10))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let progress = downloadProgress {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 80)
                    Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            } else if isDownloaded {
                HStack(spacing: 8) {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    if let onDelete {
                        Button(role: .destructive, action: { isPresentingDeleteConfirm = true }) {
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
                HStack(spacing: 8) {
                    Button("Download", action: onDownload)
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) {  $0[.leading] }
    }
}

// MARK: - Local IPSW row (unchanged)

struct LocalIPSWRow: View {
    let url: URL
    let onCreateBaseVM: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isPresentingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive.fill")
                .font(.title3).foregroundStyle(.green).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent).fontWeight(.medium)
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    Text(String(format: "%.1f GB", Double(size) / 1_073_741_824))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Create Base VM", action: onCreateBaseVM)
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
                        "Delete \"\(url.deletingPathExtension().lastPathComponent)\"?",
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
        .alignmentGuide(.listRowSeparatorLeading) {  $0[.leading] }
    }
}

// MARK: - NewBaseVMSheetWithIPSW (bridge)

struct NewBaseVMSheetWithIPSW: View {
    let preselectedIPSW: URL?
    @Environment(\.dismiss) var dismiss

    @State private var baseVMStore: BaseVMStore = {
        let settings = AppSettings.load()
        let runner   = ProcessRunner()
        let depsRoot = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps")
        let tartSvc  = TartService(runner: runner,
                                   tartPath: depsRoot.appendingPathComponent("tart").path)
        let packerSvc = PackerService(
            runner: runner,
            packerPath: depsRoot.appendingPathComponent("packer").path,
            pluginDir: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path,
            templatesRoot: settings.packerTemplatesRoot
        )
        return BaseVMStore(packerService: packerSvc, tartService: tartSvc,
                           storageRoot: settings.packerTemplatesRoot)
    }()
    @State private var theme = AppTheme()
    @State private var templateStore = PackerTemplateStore()

    var body: some View {
        NewBaseVMSheetPreloaded(preselectedIPSW: preselectedIPSW)
            .environmentObject(baseVMStore)
            .environmentObject(theme)
            .environmentObject(templateStore)
    }
}

struct NewBaseVMSheetPreloaded: View {
    let preselectedIPSW: URL?
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var templateStore: PackerTemplateStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        // Delegate to the full sheet which has all options.
        // Pre-select the IPSW source so it auto-populates OS/version.
        NewBaseVMSheet(preselectedIPSWURL: preselectedIPSW)
    }
}
