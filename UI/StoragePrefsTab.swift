import SwiftUI

struct StoragePrefsTab: View {
    @State private var settings = AppSettings.load()
    @State private var activePickerTarget: PickerTarget?
    @State private var pendingTartHome: String? = nil
    @State private var showRebuildConfirm = false

    enum PickerTarget { case vms, ipsws, templates, deps, tartHome }

    var body: some View {
        Form {
            Section {
                LabeledContent("Tart VM storage (TART_HOME)") {
                    HStack(spacing: 8) {
                        Text(settings.tartHome ?? "(default: ~/.tart)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Button {
                            let path = settings.tartHome ?? FileManager.default
                                .homeDirectoryForCurrentUser.appendingPathComponent(".tart").path
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: { Image(systemName: "folder") }
                        .controlSize(.small).help("Open in Finder")
                        Button("Change…") { activePickerTarget = .tartHome }.controlSize(.small)
                        if settings.tartHome != nil {
                            Button("Reset") { settings.tartHome = nil; try? settings.save() }
                                .controlSize(.small).tint(.secondary)
                        }
                    }
                }
                .help("Where tart stores VM disk images. Overrides the TART_HOME environment variable.")
                storageRow(label: "IPSWs",            description: "Downloaded macOS firmware.",    url: settings.ipswStorageRoot,     target: .ipsws)
                storageRow(label: "Packer templates", description: ".pkr.hcl files and scripts.",   url: settings.packerTemplatesRoot, target: .templates)
                storageRow(label: "Dependencies",     description: "tart, packer, mist-cli, jq.",   url: settings.depsRoot,            target: .deps)
            } header: { Text("Locations") }
              footer: { Text("TART_HOME can be set to an external drive to keep large VM files off your main disk. App settings always stay in ~/Library/Application Support/Oven.") }

            Section {
                Text("Clears saved VM and Base VM metadata then rebuilds from tart list. Use if VMs appear in the wrong view or metadata is out of date. Display names, tags, and descriptions will be lost.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Rebuild Metadata…") { showRebuildConfirm = true }
                        .buttonStyle(.bordered)

                }
            } header: { Text("Maintenance") }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .confirmationDialog("Rebuild Metadata?", isPresented: $showRebuildConfirm, titleVisibility: .visible) {
            Button("Rebuild & Restart", role: .destructive) {
                // Delete both metadata files using the configured storage paths
                let s = AppSettings.load()
                let vmMeta   = s.vmStorageRoot.appendingPathComponent("vms/metadata.json")
                let baseMeta = s.packerTemplatesRoot.appendingPathComponent("base-vms/metadata.json")
                try? FileManager.default.removeItem(at: vmMeta)
                try? FileManager.default.removeItem(at: baseMeta)
                AppLogger.shared.log("Metadata deleted: \(vmMeta.path)", source: "Preferences")
                AppLogger.shared.log("Metadata deleted: \(baseMeta.path)", source: "Preferences")
                // Relaunch: open a new instance then quit this one
                _ = URL(fileURLWithPath: Bundle.main.executablePath!)
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
            guard let url = try? result.get() else { return }
            switch activePickerTarget {
            case .ipsws:     settings.ipswStorageRoot = url;     try? settings.save()
            case .templates: settings.packerTemplatesRoot = url; try? settings.save()
            case .deps:      settings.depsRoot = url;            try? settings.save()
            case .tartHome:
                let oldPath = settings.tartHome
                settings.tartHome = url.path; try? settings.save()
                if oldPath != nil { pendingTartHome = oldPath }
            default: break
            }
            activePickerTarget = nil
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
    }

    @ViewBuilder
    private func storageRow(label: String, description: String, url: URL, target: PickerTarget) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text(url.abbreviatingWithTilde)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "folder") }
                    .controlSize(.small).help("Open in Finder")
                Button("Change…") { activePickerTarget = target }.controlSize(.small)
            }
        }
        .help(description)
    }

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
