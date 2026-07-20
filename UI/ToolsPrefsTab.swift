import SwiftUI

struct ToolsPrefsTab: View {
    @Environment(DependencyManager.self) private var depManager
    @State private var isCheckingNow = false

    var body: some View {
        Form {
            // MARK: Per-dependency rows
            Section {
                ForEach(depManager.dependencies) { dep in
                    ToolDepRow(dep: dep, depManager: depManager)
                }

                HStack {
                    if depManager.isCheckingForUpdates {
                        ProgressView().controlSize(.small)
                        Text("Checking for updates…").font(.caption).foregroundStyle(.secondary)
                    } else if let checked = depManager.lastUpdateCheck {
                        Text("Last checked \(checked.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Updates checked for Oven-managed tools only")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") {
                        isCheckingNow = true
                        Task {
                            await depManager.checkForUpdates()
                            isCheckingNow = false
                        }
                    }
                    .disabled(depManager.isCheckingForUpdates || isCheckingNow
                              || !depManager.dependencies.contains { $0.installMethod == .managed })
                    .controlSize(.small)
                }
            } header: { Text("Tools") }
              footer: { Text("Choose Oven-managed to let Oven download and update each tool, or Custom path to use your own binary. Updates are downloaded individually — Oven never updates tools automatically.") }
        }
        .formStyle(.grouped)
        .navigationTitle("Tools")
    }
}

// MARK: - Per-tool row

private struct ToolDepRow: View {
    let dep: Dependency
    let depManager: DependencyManager

    @State private var editingPath: String = ""

    private var isPlugin: Bool { dep.id == "tart-packer-plugin" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Status icon
                statusIcon
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dep.displayName).fontWeight(.medium)
                    if dep.isReady {
                        Group {
                            if dep.status == .updateAvailable, let latest = dep.latestVersion, let current = dep.currentVersion {
                                Text("\(current) → \(latest) available")
                                    .foregroundStyle(.orange)
                            } else if let current = dep.currentVersion {
                                Text(current).foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }

                Spacer()

                // Action buttons
                if dep.status == .updateAvailable && dep.installMethod == .managed {
                    Button("Update") {
                        Task { await depManager.install(dep) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if dep.status == .notInstalled && dep.installMethod == .managed {
                    Button("Install") {
                        Task { await depManager.install(dep) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Method picker (plugin is always managed)
                if !isPlugin {
                    Picker("", selection: methodBinding) {
                        Text("Oven-managed").tag(AppSettings.DependencyInstallSetting.Method.managed)
                        Text("Custom path").tag(AppSettings.DependencyInstallSetting.Method.custom)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .labelsHidden()
                } else {
                    Text("Oven-managed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            // Custom path editor (visible when method is .custom)
            if dep.installMethod == .custom && !isPlugin {
                HStack(spacing: 8) {
                    TextField("", text: $editingPath,
                              prompt: Text("/usr/local/bin/\(dep.displayName)").foregroundStyle(.tertiary))
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { commitPath() }

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url {
                            editingPath = url.path
                            commitPath()
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Browse for the \(dep.displayName) binary")

                    if !editingPath.isEmpty {
                        let exists = FileManager.default.fileExists(atPath: editingPath)
                        Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(exists ? .green : .red)
                            .help(exists ? "Binary found" : "Binary not found at this path")
                    }
                }
                .padding(.leading, 28)  // align under name

                if let detected = dep.detectedSystemPath {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Found at \(detected.path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Use this") {
                            editingPath = detected.path
                            commitPath()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.accent)
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .onAppear { editingPath = dep.customPath }
        .onChange(of: dep.customPath) { _, new in editingPath = new }
    }

    // MARK: - Helpers

    private var methodBinding: Binding<AppSettings.DependencyInstallSetting.Method> {
        Binding(
            get: { dep.installMethod },
            set: { newMethod in
                Task {
                    if newMethod == .custom {
                        let prefill = dep.detectedSystemPath?.path ?? dep.customPath
                        await depManager.setInstallMethod(id: dep.id, to: .custom, customPath: prefill)
                    } else {
                        await depManager.setInstallMethod(id: dep.id, to: newMethod)
                    }
                }
            }
        )
    }

    private func commitPath() {
        let path = editingPath.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await depManager.setInstallMethod(id: dep.id, to: .custom, customPath: path) }
    }

    @ViewBuilder
    private var statusIcon: some View {
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
}
