import SwiftUI

struct ToolsPrefsTab: View {
    @Environment(DependencyManager.self) private var depManager

    // Local mirror of persisted settings
    @State private var mode: AppSettings.DependencyMode = .managed
    @State private var customPaths: AppSettings.CustomBinaryPaths = AppSettings.CustomBinaryPaths()
    @State private var isCheckingNow = false

    var body: some View {
        Form {
            // MARK: Management mode
            Section {
                Picker("Dependency management", selection: $mode) {
                    Text("Managed by Oven").tag(AppSettings.DependencyMode.managed)
                    Text("Custom paths").tag(AppSettings.DependencyMode.custom)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: mode) { _, _ in saveMode() }

                if mode == .managed {
                    Text("Oven downloads and keeps tart, packer, mist-cli, and jq in its own storage folder. Updates are checked at launch and every 12 hours.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Oven uses the binaries you specify below. No updates will be checked or offered.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Tool management") }

            // MARK: Update status (managed mode only)
            if mode == .managed {
                Section {
                    ForEach(depManager.dependencies) { dep in
                        ManagedDependencyRow(dep: dep, depManager: depManager)
                    }

                    HStack {
                        if depManager.isCheckingForUpdates {
                            ProgressView().controlSize(.small)
                            Text("Checking for updates…").font(.caption).foregroundStyle(.secondary)
                        } else if let checked = depManager.lastUpdateCheck {
                            Text("Last checked \(checked.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Updates not yet checked").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Check Now") {
                            isCheckingNow = true
                            Task {
                                await depManager.checkForUpdates()
                                isCheckingNow = false
                            }
                        }
                        .disabled(depManager.isCheckingForUpdates || isCheckingNow)
                        .controlSize(.small)
                    }
                } header: { Text("Installed tools") }
                  footer: { Text("Updates are downloaded individually. Oven never updates tools automatically.") }
            }

            // MARK: Custom paths (custom mode only)
            if mode == .custom {
                Section {
                    CustomPathRow(label: "tart", path: $customPaths.tart)
                    CustomPathRow(label: "packer", path: $customPaths.packer)
                    CustomPathRow(label: "mist-cli", path: $customPaths.mistCli)
                    CustomPathRow(label: "jq", path: $customPaths.jq)
                } header: { Text("Binary paths") }
                  footer: { Text("Provide absolute paths to each binary. Oven will use these instead of its managed copies and will not check for updates.") }
                  .onChange(of: customPaths.tart)    { _, _ in saveCustomPaths() }
                  .onChange(of: customPaths.packer)  { _, _ in saveCustomPaths() }
                  .onChange(of: customPaths.mistCli) { _, _ in saveCustomPaths() }
                  .onChange(of: customPaths.jq)      { _, _ in saveCustomPaths() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tools")
        .onAppear { loadSettings() }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let s = AppSettings.load()
        mode = s.dependencyMode
        customPaths = s.customPaths
    }

    private func saveMode() {
        var s = AppSettings.load()
        s.dependencyMode = mode
        try? s.save()
        Task { await depManager.reloadSettings() }
    }

    private func saveCustomPaths() {
        var s = AppSettings.load()
        s.customPaths = customPaths
        try? s.save()
        Task { await depManager.reloadSettings() }
    }
}

// MARK: - Managed dependency row

private struct ManagedDependencyRow: View {
    let dep: Dependency
    let depManager: DependencyManager

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Group {
                switch dep.status {
                case .installed:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .updateAvailable:
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                case .installing:
                    ProgressView().controlSize(.small)
                case .notInstalled:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                case .error:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                case .skipped:
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(dep.displayName).fontWeight(.medium)
                if let current = dep.currentVersion {
                    Group {
                        if dep.status == .updateAvailable, let latest = dep.latestVersion {
                            Text("\(current) → \(latest) available")
                                .foregroundStyle(.orange)
                        } else {
                            Text(current).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }

            Spacer()

            if dep.status == .updateAvailable {
                Button("Update") {
                    Task { await depManager.install(dep) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if dep.status == .notInstalled {
                Button("Install") {
                    Task { await depManager.install(dep) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Custom path row

private struct CustomPathRow: View {
    let label: String
    @Binding var path: String

    var body: some View {
        LabeledContent(label) {
            HStack {
                TextField("", text: $path,
                          prompt: Text("/usr/local/bin/\(label)").foregroundStyle(.secondary))
                    .font(.system(.body, design: .monospaced))
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    if panel.runModal() == .OK, let url = panel.url {
                        path = url.path
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Browse for the \(label) binary")

                if !path.isEmpty {
                    Image(systemName: FileManager.default.fileExists(atPath: path)
                          ? "checkmark.circle.fill"
                          : "xmark.circle.fill")
                    .foregroundStyle(FileManager.default.fileExists(atPath: path) ? .green : .red)
                    .help(FileManager.default.fileExists(atPath: path)
                          ? "Binary found"
                          : "Binary not found at this path")
                }
            }
        }
    }
}
