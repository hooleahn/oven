import SwiftUI

// MARK: - Sort Order

private enum FirmwareSortOrder: String, CaseIterable {
    case date    = "Date"
    case size    = "Size"
    case version = "Version"
}

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
    @State private var sortOrder: FirmwareSortOrder = .date

    private var settings: AppSettings { AppSettings.load() }

    var filteredLocalIPSWs: [URL] {
        let base = searchText.isEmpty ? localIPSWs : localIPSWs.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(searchText)
        }
        switch sortOrder {
        case .date:
            return base.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
        case .size:
            return base.sorted {
                let a = (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let b = (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return a > b
            }
        case .version:
            return base.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }

    var filteredFirmwares: [IPSWFirmware] {
        let base = searchText.isEmpty ? firmwares : firmwares.filter {
            $0.displayName.lowercased().contains(searchText.lowercased())
            || $0.version.contains(searchText)
            || $0.buildid.contains(searchText)
        }
        switch sortOrder {
        case .date:    return base.sorted { $0.releasedate > $1.releasedate }
        case .size:    return base.sorted { $0.filesize > $1.filesize }
        case .version: return base.sorted { $0.version > $1.version }
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
                } content: { EmptyView() }
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
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Sort by: \(sortOrder.rawValue)")

            Button { Task {
                    await IPSWService.shared.invalidateCache()
                    // Also clear mist cache
                    let mistCache = AppSettings.defaultLocalStorageRoot
                        .appendingPathComponent("mist-firmware-cache.json")
                    try? FileManager.default.removeItem(at: mistCache)
                    await loadFirmwares()
                } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Refresh firmware list")
        }
        .padding(.horizontal, Spacing.lg - 2).padding(.vertical, Spacing.sm).background(.bar)
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
                            },
                            onCreateBaseVM: {
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
                                    selectedIPSWForBaseVM = url
                                    isPresentingBaseVMSheet = true
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

// MARK: - Firmware row (Available from Apple)

struct IPSWFirmwareRow: View {
    let firmware: IPSWFirmware
    let downloadProgress: Double?
    let isDownloaded: Bool
    let onDownload: () -> Void
    var onDelete: (() -> Void)? = nil
    var onCreateBaseVM: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var isPresentingDeleteConfirm = false

    private var formattedReleaseDate: String {
        let raw = String(firmware.releasedate.prefix(10)) // "YYYY-MM-DD"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let date = df.date(from: raw) {
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        return raw
    }

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
                            .font(.system(size: 11))
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
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                                .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))

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
    }
}

// MARK: - Local IPSW row (downloaded)

struct LocalIPSWRow: View {
    let url: URL
    let onCreateBaseVM: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isPresentingDeleteConfirm = false

    private var displayName: String { url.deletingPathExtension().lastPathComponent }

    private var formattedFileSize: String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        let gb = Double(size) / 1_073_741_824
        return String(format: "%.2f GB", gb)
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white, .green)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName).fontWeight(.medium)
                HStack(spacing: 8) {
                    // Prominent file size
                    if let size = formattedFileSize {
                        Text(size)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    // "Ready to use" status pill
                    Text("Ready to use")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(.green)
                        .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))
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
                        "Delete \"\(displayName)\"?",
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
    }
}

// MARK: - NewBaseVMSheetWithIPSW (bridge)
// Passes the real app-wide BaseVMStore through the environment so that VMs
// created here appear immediately in the Base VMs list.

struct NewBaseVMSheetWithIPSW: View {
    let preselectedIPSW: URL?

    var body: some View {
        // Environment objects (BaseVMStore, AppTheme, PackerTemplateStore, BuildingBlockStore)
        // are already injected by the presenting view via the app-level environment chain.
        NewBaseVMSheet(preselectedIPSWURL: preselectedIPSW)
    }
}
