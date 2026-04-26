import SwiftUI


struct BaseVMDetailPane: View {
    let baseVM: VirtualMachine
    let onBuild: () -> Void
    let onDelete: () -> Void
    let onCreateVM: () -> Void
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var templateStore: PackerTemplateStore
    @State private var isPresentingPushSheet = false
    @State private var pushProgress: Double? = nil
    @State private var pushError: String? = nil
    @State private var liveConfig: TartService.TartVMConfig? = nil
    @State private var isLoadingConfig = false
    @State private var isPresentingEditSheet = false
    @SceneStorage("baseVMDetailPane.logInspectorOpen") private var logInspectorOpen = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Compact header ──────────────────────────────────────────────
            headerSection

            Divider()

            // ── Grouped form ────────────────────────────────────────────────
            Form {
                Section("Configuration") {
                    // Refresh row
                    HStack(spacing: 4) {
                        Spacer()
                        if isLoadingConfig {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button { Task { await loadLiveConfig() } } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain).help("Refresh from tart")
                        }
                    }

                    LabeledContent("macOS") {
                        let label = "\(baseVM.osName.rawValue) \(baseVM.osVersion)"
                            .trimmingCharacters(in: .whitespaces)
                        Text(label.isEmpty ? baseVM.name : label)
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
                }

                Section("Credentials") {
                    LabeledContent("Username") {
                        CopyableText(baseVM.sshUsername, monospaced: true)
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
                if let prog = pushProgress {
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
        // ── Toolbar ──────────────────────────────────────────────────────────
        .toolbar {
            // Primary action: context-sensitive main CTA
            ToolbarItem(placement: .primaryAction) {
                if baseVM.buildStatus == .ready {
                    Button(action: onCreateVM) {
                        Label("Create VM", systemImage: "plus.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("Create a working VM from this base VM")
                } else if baseVM.buildStatus == .building {
                    Button(action: {}) {
                        Label("Building…", systemImage: theme.buildIcon)
                    }
                    .disabled(true)
                } else {
                    Button(action: onBuild) {
                        Label(theme.build, systemImage: theme.buildIcon)
                    }
                    .help(theme.build)
                }
            }

            // "…" menu: secondary actions
            ToolbarItem(placement: .automatic) {
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
                            .disabled(pushProgress != nil)
                        }
                        Divider()
                    }
                    Button { isPresentingEditSheet = true } label: {
                        Label("Edit…", systemImage: "pencil")
                    }
                    Divider()
                    Button {
                        logInspectorOpen.toggle()
                    } label: {
                        Label(logInspectorOpen ? "Hide Build Log" : "Show Build Log",
                              systemImage: "terminal")
                    }
                    .disabled(baseVM.buildLog.isEmpty)
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(baseVM.buildStatus == .building)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
        // ── Trailing inspector: build log ─────────────────────────────────
        .inspector(isPresented: $logInspectorOpen) {
            if baseVM.buildLog.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No build log yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .inspectorColumnWidth(min: 240, ideal: 300)
            } else {
                BuildLogView(baseVM: baseVM)
                    .inspectorColumnWidth(min: 240, ideal: 300)
            }
        }
        .task(id: baseVM.id) { await loadLiveConfig() }
        .sheet(isPresented: $isPresentingEditSheet) {
            BaseVMEditSheet(baseVM: baseVM)
                .environmentObject(baseVMStore)
                .environmentObject(vmStore)
                .environmentObject(templateStore)
        }
        .sheet(isPresented: $isPresentingPushSheet) {
            PushToRegistrySheet(vmName: baseVM.name) { imageRef, credentials in
                isPresentingPushSheet = false
                Task { await pushBaseVM(to: imageRef, credentials: credentials) }
            }
        }
        .alert("Push failed", isPresented: Binding(
            get: { pushError != nil }, set: { if !$0 { pushError = nil } }
        )) {
            Button("OK") { pushError = nil }
        } message: { Text(pushError ?? "") }
    }

    // MARK: - Header

    @ViewBuilder private var headerSection: some View {
        VStack(spacing: 4) {
            Image(systemName: baseVM.buildStatus.systemImage)
                .font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            let displayTitle: String = {
                if !baseVM.displayName.isEmpty { return baseVM.displayName }
                if baseVM.vmSource == .registry {
                    let last = (baseVM.name.components(separatedBy: "/").last ?? baseVM.name)
                    let clean = (last.components(separatedBy: ":").first ?? last)
                    return clean.replacingOccurrences(of: "macos-", with: "")
                        .replacingOccurrences(of: "-base", with: " Base")
                        .replacingOccurrences(of: "-", with: " ").capitalized
                }
                return baseVM.name
            }()
            Text(displayTitle).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            if baseVM.vmSource == .registry || !baseVM.displayName.isEmpty {
                Text(baseVM.name)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1)
            }
            if !baseVM.description.isEmpty {
                Text(baseVM.description)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            Text(baseVM.buildStatus.label)
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).background(.bar)
    }

    // MARK: - Async helpers

    @MainActor private func loadLiveConfig() async {
        let tartPath = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        isLoadingConfig = true
        let svc = TartService(runner: ProcessRunner(), tartPath: tartPath)
        if let config = try? await svc.get(name: baseVM.name) {
            liveConfig = config
        }
        isLoadingConfig = false
    }

    @MainActor private func pushBaseVM(to imageRef: String, credentials: [RegistryCredential]) async {
        let tartPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        let host = imageRef.components(separatedBy: "/").first ?? ""
        let cred = credentials.first(where: { $0.registry == host })
        pushProgress = 0.0
        pushError = nil
        var errorLines: [String] = []
        AppLogger.shared.log("Pushing \(baseVM.name) → \(imageRef)", source: "BaseVMDetailPane")
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartPath,
                                  registryUsername: cred?.username,
                                  registryPassword: cred?.password)
        let stream = await tartSvc.push(name: baseVM.name, to: imageRef)
        for await event in stream {
            switch event {
            case .stdout(let line):
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("Error:") { errorLines.append(t) }
                if line.contains("%") {
                    let digits = line.filter { $0.isNumber || $0 == "." }
                    if let pct = Double(digits) { pushProgress = min(pct / 100.0, 1.0) }
                }
                AppLogger.shared.log(line, source: "Push")
            case .stderr(let line):
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { errorLines.append(t) }
                AppLogger.shared.log(line, source: "Push")
            case .exit(let code):
                pushProgress = nil
                if code == 0 {
                    AppLogger.shared.success("Push complete: \(imageRef)", source: "BaseVMDetailPane")
                } else {
                    let raw = errorLines.joined(separator: "\n")
                    AppLogger.shared.error("Push failed (exit \(code)): \(raw)", source: "BaseVMDetailPane")
                    pushError = parseTartError(raw) ?? (raw.isEmpty ? "Push failed (exit \(code))" : raw)
                }
            }
        }
    }
}

// MARK: - CopyableText helper (inline, scoped to this file)

private struct CopyableText: View {
    let value: String
    var monospaced: Bool = false
    @State private var copied = false

    init(_ value: String, monospaced: Bool = false) {
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(.secondary)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
    }
}
