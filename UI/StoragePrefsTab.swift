import SwiftUI

// MARK: - DiskUsageEntry

private struct DiskUsageEntry: Identifiable {
    let id = UUID()
    let label: String
    let bytes: Int64
    let color: Color
    let icon: String
}

// MARK: - StoragePrefsTab

struct StoragePrefsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    @State private var settings = AppSettings.load()
    @State private var activePickerTarget: PickerTarget?
    @State private var committedPickerTarget: PickerTarget?
    @State private var pendingTartHome: String? = nil
    @State private var showRebuildConfirm = false
    @State private var diskEntries: [DiskUsageEntry] = []
    @State private var totalDiskBytes: Int64 = 0

    enum PickerTarget { case vms, ipsws, templates, deps, tartHome }

    var body: some View {
        Form {
            Section {
                tartHomeRow
                storageRow(label: "IPSWs",           description: "Downloaded macOS firmware files.", url: settings.ipswStorageRoot,     target: .ipsws,     defaultURL: AppSettings.default.ipswStorageRoot,     helpText: "Where Oven stores downloaded IPSW firmware files. These can be several GB each.")
                storageRow(label: "Packer templates", description: ".pkr.hcl files and scripts.",     url: settings.packerTemplatesRoot, target: .templates, defaultURL: AppSettings.default.packerTemplatesRoot, helpText: "Directory containing your Packer HCL templates and associated scripts.")
                storageRow(label: "Dependencies",     description: "tart, packer, mist-cli, jq.",     url: settings.depsRoot,            target: .deps,      defaultURL: AppSettings.default.depsRoot,            helpText: "Where Oven installs and manages its required tools (tart, packer, mist-cli, jq).")
            } header: {
                Text("Locations")
            } footer: {
                Text("TART_HOME can be set to an external drive to keep large VM files off your main disk. App settings always stay in ~/Library/Application Support/Oven.")
            }

            // Disk usage visualization
            if !diskEntries.isEmpty {
                Section {
                    diskUsageChart
                } header: {
                    Text("Disk Usage")
                } footer: {
                    Text("Approximate sizes read from disk. Does not include system files or the Oven app itself.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Clears saved VM and Base VM metadata then rebuilds from tart list. Use if VMs appear in the wrong view or metadata is out of date. Display names, tags, and descriptions will be lost.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Rebuild Metadata…") { showRebuildConfirm = true }
                    .buttonStyle(.bordered)
                    .help("Deletes all saved VM and Base VM metadata from disk, then relaunches Oven to rediscover VMs from tart. Custom display names, tags, and descriptions will be lost.")
            } header: { Text("Maintenance") }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .task { await computeDiskUsage() }
        .confirmationDialog("Rebuild Metadata?", isPresented: $showRebuildConfirm, titleVisibility: .visible) {
            Button("Rebuild & Restart", role: .destructive) {
                // Use AppDatabase.shared.url(for:) so the paths are always correct
                // regardless of which profile is active or where settings point.
                let vmMeta   = AppDatabase.shared.url(for: .vms)
                let baseMeta = AppDatabase.shared.url(for: .baseVMs)
                try? FileManager.default.removeItem(at: vmMeta)
                try? FileManager.default.removeItem(at: baseMeta)
                AppLogger.shared.log("Metadata deleted: \(vmMeta.path)", source: "Preferences")
                AppLogger.shared.log("Metadata deleted: \(baseMeta.path)", source: "Preferences")
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = ["-n", Bundle.main.bundlePath]
                try? proc.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    SharedStores.skipQuitGuard = true
                    NSApplication.shared.terminate(nil)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Oven will delete all saved VM and Base VM metadata, then restart. Display names, tags, and descriptions will be lost. VMs and Base VMs will be rediscovered from tart on relaunch.")
        }
        .fileImporter(
            isPresented: Binding(get: { activePickerTarget != nil }, set: { if !$0 { activePickerTarget = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            defer { activePickerTarget = nil; committedPickerTarget = nil }
            guard let url = try? result.get() else { return }
            switch committedPickerTarget {
            case .ipsws:
                settings.ipswStorageRoot = url; try? settings.save()
                let ipswURL = url, pid = profileStore.activeProfileID
                Task { @MainActor in profileStore.setIPSWRoot(id: pid, to: ipswURL) }
            case .templates:
                settings.packerTemplatesRoot = url; try? settings.save()
                let tmplURL = url, pid = profileStore.activeProfileID
                Task { @MainActor in profileStore.setPackerTemplatesRoot(id: pid, to: tmplURL) }
            case .deps:      settings.depsRoot = url;            try? settings.save()
            case .tartHome:
                let oldPath = settings.tartHome
                settings.tartHome = url.path; try? settings.save()
                if oldPath != nil { pendingTartHome = oldPath }
            default: break
            }
        }
        .alert("Copy VMs to new location?", isPresented: Binding(
            get: { pendingTartHome != nil }, set: { if !$0 { pendingTartHome = nil } }
        )) {
            Button("Copy") {
                if let old = pendingTartHome, let new = settings.tartHome { copyTartHome(from: old, to: new) }
                pendingTartHome = nil
            }
            Button("Don't copy", role: .cancel) { pendingTartHome = nil }
        } message: {
            Text("Do you want to copy your existing tart VMs to the new location? This may take a while for large VMs.")
        }
        .onChange(of: settings.ipswStorageRoot) { _, newURL in
            let isDefault = newURL == AppSettings.default.ipswStorageRoot
            profileStore.setIPSWRoot(id: profileStore.activeProfileID, to: isDefault ? nil : newURL)
        }
        .onChange(of: settings.packerTemplatesRoot) { _, newURL in
            let isDefault = newURL == AppSettings.default.packerTemplatesRoot
            profileStore.setPackerTemplatesRoot(id: profileStore.activeProfileID, to: isDefault ? nil : newURL)
        }
        .onChange(of: profileStore.activeProfile) { _, _ in
            settings = AppSettings.load()
        }
    }

    // MARK: - TART_HOME row (special: has Reset)

    private var tartHomeRow: some View {
        LabeledContent("Tart VM storage (TART_HOME)") {
            HStack(spacing: 8) {
                // Validation icon
                pathValidationIcon(for: settings.tartHome.map { URL(fileURLWithPath: $0) }
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tart"))

                Text(settings.tartHome ?? "(default: ~/.tart)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)

                Button { NSWorkspace.shared.open(URL(fileURLWithPath:
                    settings.tartHome ?? FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".tart").path))
                } label: { Image(systemName: "folder") }
                .controlSize(.small).help("Open in Finder")

                Button("Change…") { committedPickerTarget = .tartHome; activePickerTarget = .tartHome }.controlSize(.small)

                if settings.tartHome != nil {
                    Button("Reset") { settings.tartHome = nil; try? settings.save() }
                        .controlSize(.small).tint(.secondary)
                        .help("Revert to the default ~/.tart location")
                }
            }
        }
        .help("Where tart stores VM disk images. Overrides the TART_HOME environment variable.")
    }

    // MARK: - Generic storage row

    @ViewBuilder
    private func storageRow(label: String, description: String, url: URL, target: PickerTarget, defaultURL: URL, helpText: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                pathValidationIcon(for: url)

                Text(url.abbreviatingWithTilde)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)

                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "folder") }
                    .controlSize(.small).help("Open in Finder")

                Button("Change…") { committedPickerTarget = target; activePickerTarget = target }.controlSize(.small)

                if url != defaultURL {
                    Button("Reset") {
                        switch target {
                        case .ipsws:
                            settings.ipswStorageRoot = defaultURL; try? settings.save()
                        case .templates:
                            settings.packerTemplatesRoot = defaultURL; try? settings.save()
                        case .deps:
                            settings.depsRoot = defaultURL; try? settings.save()
                        default: break
                        }
                    }
                    .controlSize(.small).tint(.secondary)
                    .help("Revert to the default location")
                }
            }
        }
        .help(helpText)
    }

    // MARK: - Path validation icon

    @ViewBuilder
    private func pathValidationIcon(for url: URL) -> some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let isDir  = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if exists && isDir {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Directory exists")
        } else if exists && !isDir {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help("Path exists but is not a directory")
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("Directory not found — it will be created on first use")
        }
    }

    // MARK: - Disk usage chart

    private var diskUsageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(diskEntries) { entry in
                        if entry.bytes > 0 && totalDiskBytes > 0 {
                            let fraction = CGFloat(entry.bytes) / CGFloat(totalDiskBytes)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(entry.color)
                                .frame(width: max(4, geo.size.width * fraction))
                                .help("\(entry.label): \(formattedBytes(entry.bytes))")
                        }
                    }
                }
            }
            .frame(height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend
            VStack(alignment: .leading, spacing: 6) {
                ForEach(diskEntries) { entry in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.color)
                            .frame(width: 12, height: 12)
                        Image(systemName: entry.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(entry.label)
                            .font(.caption)
                        Spacer()
                        Text(formattedBytes(entry.bytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Divider()

                HStack {
                    Text("Total tracked").font(.caption).fontWeight(.medium)
                    Spacer()
                    Text(formattedBytes(totalDiskBytes))
                        .font(.caption).fontWeight(.medium)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Disk usage computation

    private func computeDiskUsage() async {
        let s = AppSettings.load()

        // Tart VMs (TART_HOME/vms)
        let vmDir = s.resolvedTartHome.appendingPathComponent("vms")
        let vmBytes = await directorySize(vmDir)

        // IPSWs
        let ipswBytes = await directorySize(s.ipswStorageRoot)

        // Base VMs in packer templates root
        let baseVMDir = s.packerTemplatesRoot.appendingPathComponent("base-vms")
        let baseVMBytes = await directorySize(baseVMDir)

        let entries: [DiskUsageEntry] = [
            DiskUsageEntry(label: "Virtual Machines", bytes: vmBytes,     color: .blue,   icon: "desktopcomputer"),
            DiskUsageEntry(label: "Base VM files",    bytes: baseVMBytes, color: .orange, icon: "shippingbox"),
            DiskUsageEntry(label: "IPSW Firmwares",   bytes: ipswBytes,   color: .purple, icon: "arrow.down.circle"),
        ].filter { $0.bytes > 0 }

        let total = entries.reduce(0) { $0 + $1.bytes }

        await MainActor.run {
            diskEntries    = entries
            totalDiskBytes = total
        }
    }

    private func directorySize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
            var total: Int64 = 0
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                          vals.isRegularFile == true,
                          let size = vals.fileSize else { continue }
                    total += Int64(size)
                }
            }
            return total
        }.value
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes / 1024) KB"
    }

    // MARK: - Copy TART_HOME

    private func copyTartHome(from oldPath: String, to newPath: String) {
        Task {
            let src = URL(fileURLWithPath: oldPath).appendingPathComponent("vms")
            let dst = URL(fileURLWithPath: newPath).appendingPathComponent("vms")
            do {
                try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
                let items = try FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
                for item in items {
                    let target = dst.appendingPathComponent(item.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.copyItem(at: item, to: target)
                    }
                }
                AppLogger.shared.success("Copied \(items.count) VMs to \(newPath)", source: "Preferences")
            } catch {
                AppLogger.shared.error("Copy failed: \(error.localizedDescription)", source: "Preferences")
            }
        }
    }
}
