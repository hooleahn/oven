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

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity).padding(14).background(.bar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSection("Configuration") {
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
                        .padding(.horizontal, 14)
                        DetailRow("macOS", "\(baseVM.osName.rawValue) \(baseVM.osVersion)".trimmingCharacters(in: .whitespaces).isEmpty ? baseVM.name : "\(baseVM.osName.rawValue) \(baseVM.osVersion)")
                        let cpu  = liveConfig?.cpu.map    { "\($0) vCPU" }  ?? "\(baseVM.cpuCount) cores"
                        let mem  = liveConfig?.memory.map { "\($0 / 1024) GB" } ?? "\(baseVM.memoryGB) GB"
                        let diskMax = liveConfig?.disk.map { "\($0) GB" } ?? "\(baseVM.diskGB) GB"
                        DetailRow("CPU", cpu)
                        DetailRow("Memory", mem)
                        DetailRow("Disk", diskMax)
                        if let display = liveConfig?.display { DetailRow("Display", display) }
                        if let ipsw = baseVM.ipswLocalPath {
                            DetailRow("IPSW", URL(fileURLWithPath: ipsw).lastPathComponent)
                        }
                    }
                    DetailSection("Credentials") {
                        DetailRow("Username", baseVM.sshUsername, monospaced: true, copyable: true)
                        DetailRow("Password", baseVM.sshPassword != nil ? "Stored in Keychain" : "Not set")
                        DetailRow("Auto-login", baseVM.enableAutoLogin ? "Yes" : "No")
                    }
                    DetailSection("Provisioning") {
                        DetailRow("Rosetta 2",        baseVM.installRosetta ? "Yes" : "No")
                        DetailRow("Homebrew",         baseVM.installHomebrew ? "Yes" : "No")
                        DetailRow("SSH",              baseVM.enableSSHDaemon ? "Yes" : "No")
                        DetailRow("Passwordless sudo",baseVM.enablePasswordlessSudo ? "Yes" : "No")
                        if let xcode = baseVM.xcodeVersion { DetailRow("Xcode", xcode) }
                    }
                    if theme.mdmEnabled && baseVM.mdmProfileID != nil {
                        DetailSection("MDM") {
                            DetailRow("Enrollment", "Configured")
                        }
                    }
                    if !baseVM.buildLog.isEmpty {
                        DetailSection("Last build log") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(Array(baseVM.buildLog.suffix(30).enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(8)
                            }
                            .frame(height: 140)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 14).padding(.bottom, 8)
                        }
                    }
                }
            }
            // Live build log — shown while building or after a failure
            if (baseVM.buildStatus == .building || baseVM.buildStatus == .error),
               !baseVM.buildLog.isEmpty {
                Divider()
                BuildLogView(baseVM: baseVM)
            }

            Divider()
            VStack(spacing: 6) {
                if baseVM.buildStatus == .ready {
                    Button(action: onCreateVM) {
                        Label("Create VM", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                if baseVM.buildStatus == .ready {
                    Button(action: onBuild) {
                        Label("\(theme.build) again", systemImage: theme.buildIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(false)
                } else {
                    Button(action: onBuild) {
                        Label(theme.build, systemImage: theme.buildIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(baseVM.buildStatus == .building)
                }
                Button {
                    isPresentingEditSheet = true
                } label: {
                    Label("Edit…", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
                .disabled(baseVM.buildStatus == .building)
                .help(baseVM.buildStatus == .building ? "Cannot delete while building" : "Delete base VM")

                // Push only available for locally-built VMs
                if baseVM.vmSource == .local && baseVM.buildStatus == .ready {
                    if let prog = pushProgress {
                        VStack(spacing: 4) {
                            ProgressView(value: prog).progressViewStyle(.linear)
                            Text("Pushing… \(Int(prog * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            isPresentingPushSheet = true
                        } label: {
                            Label("Push to Registry…", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let err = pushError {
                    Label(err, systemImage: "xmark.circle.fill")
                        .font(.caption).foregroundStyle(.red).lineLimit(3)
                }
            }
            .padding(12)
        }
        .background(.windowBackground)
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
