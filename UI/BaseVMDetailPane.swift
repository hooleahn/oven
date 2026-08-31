import SwiftUI


struct BaseVMDetailPane: View {
    let baseVM: VirtualMachine
    let onBuild: () -> Void
    let onDelete: () -> Void
    let onCreateVM: () -> Void
    @Environment(AppTheme.self) private var theme
    @Environment(BaseVMStore.self) private var baseVMStore
    @Environment(VMStore.self) private var vmStore
    @Environment(PackerTemplateStore.self) private var templateStore
    @Environment(PushManager.self) private var pushManager
    @Environment(DependencyManager.self) private var depManager
    @State private var isPresentingPushSheet = false
    @State private var liveConfig: TartService.TartVMConfig? = nil
    @State private var isLoadingConfig = false
    @State private var isPresentingEditSheet = false
    @State private var isPresentingLogWindow = false

    private var displayTitle: String {
        if !baseVM.displayName.isEmpty { return baseVM.displayName }
        if baseVM.vmSource == .registry {
            let last = (baseVM.name.components(separatedBy: "/").last ?? baseVM.name)
            let clean = (last.components(separatedBy: ":").first ?? last)
            return clean.replacing("macos-", with: "")
                .replacing("-base", with: " Base")
                .replacing("-", with: " ").capitalized
        }
        return baseVM.name
    }

    private var shouldShowMonoName: Bool {
        baseVM.vmSource == .registry || !baseVM.displayName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Compact header ──────────────────────────────────────────────
            // Actions live in the pane itself (not the window toolbar) — this pane
            // and BaseVMView both sit in the same NavigationSplitView, and two
            // competing .primaryAction toolbar items caused the whole toolbar to
            // swap contents depending on selection. Matches the pattern already
            // used by TemplateDetailPane / VarsFileDetailPane.
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle).font(.title3).fontWeight(.semibold)
                    if shouldShowMonoName {
                        Text(baseVM.name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    buildStatusCapsule
                }
                Spacer()
                pushProgressIndicator
                primaryActionButton
                moreActionsMenu
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if !baseVM.description.isEmpty {
                Text(baseVM.description)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }

            Divider()

            // ── Grouped form ────────────────────────────────────────────────
            Form {
                Section {
                    LabeledContent("macOS") {
                        let label = baseVM.osDisplayLabel
                        Text(label == "—" ? baseVM.name : label)
                            .foregroundStyle(.secondary)
                    }
                    let cpu  = liveConfig?.cpu.map    { "\($0) vCPU" }  ?? "\(baseVM.cpuCount) cores"
                    let mem  = liveConfig?.memory.map { "\($0 / 1024) GB" } ?? "\(baseVM.memoryGB) GB"
                    let disk = liveConfig?.disk.map   { "\($0) GB" }    ?? "\(baseVM.diskGB) GB"
                    LabeledContent("CPU")    { Text(cpu).foregroundStyle(.secondary) }
                    LabeledContent("Memory") { Text(mem).foregroundStyle(.secondary) }
                    LabeledContent("Disk")   { Text(disk).foregroundStyle(.secondary) }
                    if let display = liveConfig?.display {
                        LabeledContent("Display") { Text(display).foregroundStyle(.secondary) }
                    }
                    if let ipsw = baseVM.ipswLocalPath {
                        LabeledContent("IPSW") {
                            Text(URL(fileURLWithPath: ipsw).lastPathComponent)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Configuration")
                        Spacer()
                        if isLoadingConfig {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button(action: { Task { await loadLiveConfig() } }) {
                                Image(systemName: "arrow.clockwise").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Reload Configuration")
                            .accessibilityLabel("Reload Configuration")
                        }
                    }
                }

                Section("Credentials") {
                    LabeledContent("Username") {
                        SelectableMonoText(baseVM.sshUsername)
                    }
                    LabeledContent("Password") {
                        Text(baseVM.sshPassword != nil ? "Stored in Keychain" : "Not set")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Auto-login") {
                        Text(baseVM.enableAutoLogin ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Provisioning") {
                    LabeledContent("Rosetta 2")          { Text(baseVM.installRosetta ? "Yes" : "No").foregroundStyle(.secondary) }
                    LabeledContent("Homebrew")           { Text(baseVM.installHomebrew ? "Yes" : "No").foregroundStyle(.secondary) }
                    LabeledContent("SSH")                { Text(baseVM.enableSSHDaemon ? "Yes" : "No").foregroundStyle(.secondary) }
                    LabeledContent("Passwordless sudo")  { Text(baseVM.enablePasswordlessSudo ? "Yes" : "No").foregroundStyle(.secondary) }
                    if let xcode = baseVM.xcodeVersion {
                        LabeledContent("Xcode") { Text(xcode).foregroundStyle(.secondary) }
                    }
                }

                if theme.mdmEnabled && baseVM.mdmProfileID != nil {
                    Section("MDM") {
                        LabeledContent("Enrollment") {
                            Text("Configured").foregroundStyle(.secondary)
                        }
                    }
                }

                // Push progress (shown when a push is in-flight)
                if let prog = pushManager.active[baseVM.name] {
                    Section {
                        VStack(spacing: 4) {
                            ProgressView(value: prog).progressViewStyle(.linear)
                            Text("Pushing… \(Int(prog * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .background(.windowBackground)
        // ── Build log modal window ────────────────────────────────────────
        .sheet(isPresented: $isPresentingLogWindow) {
            BuildLogWindow(baseVM: baseVM)
        }
        .task(id: baseVM.id) { await loadLiveConfig() }
        .sheet(isPresented: $isPresentingEditSheet) {
            BaseVMEditSheet(baseVM: baseVM)
                .environment(baseVMStore)
                .environment(vmStore)
                .environment(templateStore)
        }
        .sheet(isPresented: $isPresentingPushSheet) {
            PushToRegistrySheet(vmName: baseVM.name) { imageRef, credentials in
                isPresentingPushSheet = false
                let tartPath = depManager.dependencies.first { $0.id == "tart" }?.location
                    ?? AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart").path
                Task { await pushManager.push(baseVM: baseVM, to: imageRef,
                                              credentials: credentials, tartPath: tartPath) }
            }
        }
        .alert("Push failed", isPresented: Binding(
            get: { pushManager.errors[baseVM.name] != nil },
            set: { if !$0 { pushManager.clearError(for: baseVM.name) } }
        )) {
            Button("OK") { pushManager.clearError(for: baseVM.name) }
        } message: { Text(pushManager.errors[baseVM.name] ?? "") }
    }

    // MARK: - Header actions

    private var buildStatusCapsule: some View {
        let tint = capsuleTint(for: baseVM.buildStatus)
        return Text(baseVM.buildStatus.label)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5) }
    }

    @ViewBuilder private var pushProgressIndicator: some View {
        if pushManager.active[baseVM.name] != nil {
            ProgressView()
                .controlSize(.small)
                .help("Pushing to registry…")
        }
    }

    @ViewBuilder private var primaryActionButton: some View {
        if baseVM.buildStatus == .ready {
            Button(action: onCreateVM) {
                Label("Create VM", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .help("Create a working VM from this base VM")
        } else if baseVM.buildStatus == .building {
            Button(action: {}) {
                Label("Building…", systemImage: theme.buildIcon)
            }
            .buttonStyle(.bordered)
            .disabled(true)
        } else {
            Button(action: onBuild) {
                Label(theme.build, systemImage: theme.buildIcon)
            }
            .buttonStyle(.bordered)
            .help(theme.build)
        }
    }

    @ViewBuilder private var moreActionsMenu: some View {
        Menu {
            if baseVM.buildStatus == .ready {
                Button { onBuild() } label: {
                    Label("\(theme.build) Again", systemImage: theme.buildIcon)
                }
                if baseVM.vmSource == .local {
                    Divider()
                    Button { isPresentingPushSheet = true } label: {
                        Label("Push to Registry…", systemImage: "arrow.up.circle")
                    }
                    .disabled(pushManager.active[baseVM.name] != nil)
                }
                Divider()
            }
            Button { isPresentingEditSheet = true } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Divider()
            Button {
                isPresentingLogWindow = true
            } label: {
                Label("Show Build Log", systemImage: "terminal")
            }

            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(baseVM.buildStatus == .building)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    // MARK: - Helpers

    private func capsuleTint(for status: VirtualMachine.BuildStatus) -> Color {
        switch status {
        case .ready:    return .green
        case .building: return .blue
        case .error:    return .red
        default:        return .secondary
        }
    }

    // MARK: - Async helpers

    @MainActor private func loadLiveConfig() async {
        let tartPath = depManager.dependencies.first { $0.id == "tart" }?.location
            ?? AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        isLoadingConfig = true
        let svc = TartService(runner: ProcessRunner(), tartPath: tartPath)
        if let config = try? await svc.get(name: baseVM.name) {
            liveConfig = config
        }
        isLoadingConfig = false
    }

}

// MARK: - Build Log Window

struct BuildLogWindow: View {
    let baseVM: VirtualMachine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Log")
                        .font(.headline)
                    Text(baseVM.displayName.isEmpty ? baseVM.name : baseVM.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            if baseVM.buildLog.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(.title, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No build log")
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    Text(baseVM.buildStatus == .ready
                         ? "This VM was imported from a registry."
                         : "Run a build to populate the log.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BuildLogView(baseVM: baseVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 500)
    }
}

