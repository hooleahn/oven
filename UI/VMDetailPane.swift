import SwiftUI
import AppKit
import LocalAuthentication


struct VMDetailPane: View {
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var serverStore: MDMServerStore
    @EnvironmentObject var theme: AppTheme
    let vm: VirtualMachine
    let onDismiss: () -> Void
    let onStart: () -> Void
    @State private var isPresentingPushSheet = false
    @State private var pushProgress: Double? = nil
    @State private var pushError: String? = nil
    @State private var pushTask: Task<Void, Never>? = nil
    @State private var liveConfig: TartService.TartVMConfig? = nil
    @State private var isLoadingConfig = false
    @State private var confirmStop: VirtualMachine? = nil
    @SceneStorage("vmDetailPane.logInspectorOpen") private var logInspectorOpen = false
    @State private var isPresentingExecSheet = false
    @State private var execInitialMethod: ExecMethod = .ssh

    // Service reachability
    @State private var vncReachable: Bool? = nil
    @State private var sshReachable: Bool? = nil
    @State private var isCheckingPorts = false

    // Password reveal
    @State private var revealedPassword: String? = nil
    @State private var isAuthenticating = false

    // MDM enrollment status
    @State private var enrollmentStatus: JamfEnrollmentStatus? = nil
    @State private var enrollmentError: String? = nil
    @State private var isLookingUpEnrollment = false

    /// True when serial number is long enough, an MDM server is linked, and the feature is enabled
    private var canLookUpEnrollment: Bool {
        guard vm.serialNumber.count >= 10, let serverID = vm.mdmServerID else { return false }
        return serverStore.servers.first(where: { $0.id == serverID })?.featureCheckEnrollment ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Compact header ──────────────────────────────────────────────
            headerSection

            Divider()

            // ── Grouped form ────────────────────────────────────────────────
            detailForm
        }
        .background(.windowBackground)
        .background(.bar, in: Rectangle())
        // ── Toolbar ─────────────────────────────────────────────────────────
        .toolbar {
            // Primary action: context-sensitive main CTA
            ToolbarItem(placement: .primaryAction) {
                if vm.status == .running {
                    Button {
                        if !vm.isStopping { confirmStop = vm }
                    } label: {
                        if vm.isStopping {
                            Label("Stopping…", systemImage: "stop.fill")
                        } else {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    }
                    .tint(.red)
                    .disabled(vm.isStopping)
                } else if vm.status == .suspended {
                    Button {
                        if !vm.isStopping { confirmStop = vm }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                    .disabled(vm.isStopping)
                } else {
                    Button(action: onStart) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

            // "…" menu: secondary actions
            ToolbarItem(placement: .automatic) {
                Menu {
                    // SSH — only when running with IP
                    if vm.status == .running {
                        Button {
                            openSSH(vm: vm)
                        } label: {
                            Label("Open SSH in Terminal", systemImage: "terminal")
                        }
                        .disabled(vm.ipAddress == nil)

                        Button {
                            execInitialMethod = .ssh
                            isPresentingExecSheet = true
                        } label: {
                            Label("Execute command via SSH…", systemImage: "terminal")
                        }
                        .disabled(vm.ipAddress == nil)

                        if vm.supportsGuestAgent {
                            Button {
                                execInitialMethod = .guestAgent
                                isPresentingExecSheet = true
                            } label: {
                                Label("Execute command via Tart Guest Agent…", systemImage: "bolt.horizontal.circle")
                            }
                        }

                        Button {
                            Task { await vmStore.refreshIP(for: vm) }
                        } label: {
                            Label(vm.ipAddress.map { $0.isEmpty ? "Resolving IP…" : "Refresh IP" } ?? "Resolve IP",
                                  systemImage: "arrow.clockwise")
                        }
                        .disabled(vm.isResolvingIP)

                        Divider()
                    }

                    // Push to registry (stopped only)
                    if vm.status == .stopped {
                        Button { isPresentingPushSheet = true } label: {
                            Label("Push to Registry…", systemImage: "arrow.up.circle")
                        }
                        .disabled(pushProgress != nil)
                        Divider()
                    }

                    Button {
                        logInspectorOpen.toggle()
                    } label: {
                        Label(logInspectorOpen ? "Hide Build Log" : "Show Build Log",
                              systemImage: "terminal")
                    }
                    .disabled(vm.buildLog.isEmpty)

                    Button {
                        vmStore.update(id: vm.id) { $0.isPinned.toggle() }
                    } label: {
                        Label(vm.isPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar",
                              systemImage: vm.isPinned ? "pin.slash" : "pin")
                    }

                    Divider()
                    Button(role: .destructive) {
                        // Surface deletion through the parent (VMListView holds confirmDelete)
                        onDismiss()
                    } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
        // ── Trailing inspector: build log ────────────────────────────────────
        .inspector(isPresented: $logInspectorOpen) {
            if vm.buildLog.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(.title, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No build log")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .inspectorColumnWidth(min: 240, ideal: 300)
            } else {
                BuildLogView(baseVM: vm)
                    .inspectorColumnWidth(min: 240, ideal: 300)
            }
        }
        .sheet(isPresented: $isPresentingPushSheet) {
            PushToRegistrySheet(vmName: vm.name) { imageRef, credentials in
                isPresentingPushSheet = false
                pushTask = Task { await pushVM(to: imageRef, credentials: credentials) }
            }
        }
        .sheet(isPresented: $isPresentingExecSheet) {
            ExecuteCommandSheet(vm: vm, initialMethod: execInitialMethod)
        }
        .alert("Push failed", isPresented: Binding(
            get: { pushError != nil }, set: { if !$0 { pushError = nil } }
        )) {
            Button("OK") { pushError = nil }
        } message: { Text(pushError ?? "") }
        .confirmationDialog(
            "Stop \(vm.displayName.isEmpty ? vm.name : vm.displayName)?",
            isPresented: Binding(get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } }),
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                confirmStop = nil
                Task { try? await vmStore.stop(vm: vm) }
            }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        } message: {
            Text("The VM will be sent a shutdown signal and given 30 seconds to stop gracefully.")
        }
        .task(id: vm.id) {
            // Reset transient state when VM selection changes
            enrollmentStatus = nil
            enrollmentError  = nil
            revealedPassword = nil
            // Start IP polling when detail pane opens for a running VM (skip if already exhausted)
            if vm.status == .running && (vm.ipAddress == nil || vm.ipAddress?.isEmpty == true)
                && !vm.ipPollingExhausted {
                await vmStore.refreshIP(for: vm)
            }
            await loadLiveConfig()
            // Auto-look up enrollment status if eligible
            if canLookUpEnrollment {
                await lookUpEnrollment()
            }
        }
        .onChange(of: vm.status) { _, newStatus in
            guard newStatus == .running else { return }
            guard vm.ipAddress == nil else { return }
            guard !vm.ipPollingExhausted else { return }
            Task { await vmStore.refreshIP(for: vm) }
        }
        .task(id: vm.ipAddress) {
            await checkServiceReachability()
        }
    }


    // MARK: - Detail form

    private var detailForm: some View {
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
                        .buttonStyle(.plain)
                        .help("Refresh from tart")
                    }
                }

                let cpu = liveConfig?.cpu.map { "\($0) vCPU" } ?? "\(vm.cpuCount) vCPU"
                let rawMem = liveConfig?.memory
                let mem = rawMem.map { "\($0 / 1024) GB" } ?? "\(vm.memoryGB) GB"
                let diskMax = liveConfig?.disk.map { "\($0) GB" } ?? "\(vm.diskGB) GB"
                let disk = vm.actualDiskGB.map { "\(diskMax) max · \($0) GB used" } ?? diskMax
                let osLabel = vm.osDisplayLabel

                LabeledContent("CPU")    { Text(cpu).foregroundStyle(.secondary) }
                LabeledContent("Memory") { Text(mem).foregroundStyle(.secondary) }
                LabeledContent("Disk")   { Text(disk).foregroundStyle(.secondary) }
                LabeledContent("macOS")  { Text(osLabel).foregroundStyle(.secondary) }
                if let display = liveConfig?.display {
                    LabeledContent("Display") { Text(display).foregroundStyle(.secondary) }
                }
                LabeledContent("S/N") {
                    Text(vm.serialNumber.isEmpty ? "—" : vm.serialNumber)
                        .foregroundStyle(.secondary)
                    if !vm.serialNumber.isEmpty {
                        CopyButton(value: vm.serialNumber)
                    }
                }
            }

            Section("Connectivity") {
                LabeledContent("IP Address") {
                    if vm.status == .running, let ip = vm.ipAddress, !ip.isEmpty {
                        HStack(spacing: 6) {
                            SelectableMonoText(ip)
                            CopyButton(value: ip)
                        }
                    } else if vm.status == .running && vm.isResolvingIP {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Resolving…").foregroundStyle(.secondary).font(.caption)
                        }
                    } else if vm.status == .running && vm.ipPollingExhausted {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                            Text(vm.ipAddressError ?? "Could not resolve IP address")
                                .foregroundStyle(.secondary).font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                Task { await vmStore.refreshIP(for: vm) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Retry IP resolution")
                        }
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                if vm.status == .running, let ip = vm.ipAddress, !ip.isEmpty {
                    let sshUser = vm.sshUsername.isEmpty ? "baker" : vm.sshUsername
                    let vncURL = vm.sshUsername.isEmpty ? "vnc://\(ip)" : "vnc://\(vm.sshUsername)@\(ip)"
                    LabeledContent("VNC") {
                        HStack(spacing: 6) {
                            SelectableMonoText(vncURL)
                            PortStatusDot(reachable: vncReachable, isChecking: isCheckingPorts)
                            CopyButton(value: vncURL)
                            Button {
                                if let url = URL(string: vncURL) { NSWorkspace.shared.open(url) }
                            } label: {
                                Image(systemName: "inset.filled.rectangle.and.person.filled")
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                            .help("Open Screensharing")
                        }
                    }

                    let sshCmd = "ssh \(sshUser)@\(ip)"
                    LabeledContent("SSH") {
                        HStack(spacing: 6) {
                            SelectableMonoText(sshCmd)
                            PortStatusDot(reachable: sshReachable, isChecking: isCheckingPorts)
                            CopyButton(value: sshCmd)
                            Button {
                                openSSH(vm: vm)
                            } label: {
                                Image(systemName: "apple.terminal")
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                            .help("Start SSH Session in Terminal")
                        }
                    }
                } else {
                    LabeledContent("SSH") { Text("—").foregroundStyle(.secondary) }
                }
            }

            Section("Credentials") {
                if !vm.sshUsername.isEmpty {
                    LabeledContent("Username") {
                        HStack(spacing: 6) {
                            SelectableMonoText(vm.sshUsername)
                            CopyButton(value: vm.sshUsername)
                        }
                    }
                }
                if vm.sshPassword != nil {
                    LabeledContent("Password") {
                        HStack(spacing: 6) {
                            if let pwd = revealedPassword {
                                SelectableMonoText(pwd)
                                CopyButton(value: pwd)
                                Button {
                                    revealedPassword = nil
                                } label: {
                                    Image(systemName: "eye.slash")
                                }
                                .buttonStyle(.bordered).controlSize(.mini)
                                .help("Hide password")
                            } else {
                                Text("Stored in Keychain").foregroundStyle(.secondary)
                                if isAuthenticating {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Button {
                                        Task { await revealPassword() }
                                    } label: {
                                        Image(systemName: "eye")
                                    }
                                    .buttonStyle(.bordered).controlSize(.mini)
                                    .help("Reveal password")
                                }
                            }
                        }
                    }
                }
            }

            Section("Properties") {
                if !vm.description.isEmpty {
                    LabeledContent("Description") {
                        Text(vm.description)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
                if !vm.displayName.isEmpty && vm.displayName != vm.name {
                    LabeledContent("Display name") {
                        Text(vm.displayName).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Tart name") {
                    SelectableMonoText(vm.name)
                    CopyButton(value: vm.name)
                }
                LabeledContent("Created") {
                    Text(vm.createdAt.formatted(date: .numeric, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Last started") {
                    Text(vm.lastStartedAt.map {
                        $0.formatted(date: .numeric, time: .shortened)
                    } ?? "Never")
                    .foregroundStyle(.secondary)
                }
                if !vm.tags.isEmpty {
                    LabeledContent("Tags") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(vm.tags.enumerated()), id: \.offset) { _, tag in
                                    TagChip(tag: tag)
                                }
                            }
                        }
                    }
                }
            }

            // Origin: base VM it was cloned from
            if let baseID = vm.baseVMID,
               let baseVM = baseVMStore.baseVMs.first(where: { $0.id == baseID }) {
                Section("Origin") {
                    LabeledContent("Base VM") { Text(baseVM.name).foregroundStyle(.secondary) }
                    LabeledContent("macOS") {
                        Text("\(baseVM.osName.rawValue) \(baseVM.osVersion)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MDM enrollment
            if theme.mdmEnabled && (vm.mdmProfileID != nil || vm.mdmServerID != nil || canLookUpEnrollment) {
                Section("MDM") {
                    if let serverID = vm.mdmServerID,
                       let server = serverStore.servers.first(where: { $0.id == serverID }) {
                        LabeledContent("Server") {
                            Text(server.friendlyName).foregroundStyle(.secondary)
                        }
                    }
                    if let profileID = vm.mdmProfileID,
                       let name = loadProfileName(id: profileID) {
                        LabeledContent("Profile") {
                            Text(name).foregroundStyle(.secondary)
                        }
                    }
                    if canLookUpEnrollment {
                        MDMEnrollmentStatusRow(
                            vm: vm,
                            server: serverStore.servers.first(where: { $0.id == vm.mdmServerID }),
                            status: enrollmentStatus,
                            error: enrollmentError,
                            isLoading: isLookingUpEnrollment
                        ) {
                            Task { await lookUpEnrollment() }
                        }
                    }
                }
            }

            if let ref = vm.registryImageRef {
                Section("Registry") {
                    LabeledContent("Image") { Text(ref).foregroundStyle(.secondary) }
                }
            }

            // Push progress (shown when a push is in-flight)
            if let prog = pushProgress {
                Section {
                    VStack(spacing: 6) {
                        ProgressView(value: prog).progressViewStyle(.linear)
                        HStack {
                            Text("Pushing… \(Int(prog * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                pushTask?.cancel()
                                pushTask = nil
                                pushProgress = nil
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Header

    @ViewBuilder private var headerSection: some View {
        VStack(spacing: 4) {
//            Image(systemName: "desktopcomputer")
//                .font(.system(.title, weight: .light))
//                .foregroundStyle(.secondary)
            Text(vm.displayName.isEmpty ? vm.name : vm.displayName)
                .font(.headline).lineLimit(2).multilineTextAlignment(.center)
            if !vm.displayName.isEmpty && vm.displayName != vm.name {
                Text(vm.name)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary).lineLimit(1)
            }
            StatusPill(status: vm.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Helpers

    private func openSSH(vm: VirtualMachine) {
        guard let ip = vm.ipAddress, !ip.isEmpty else { return }
        let user = vm.sshUsername.isEmpty ? "baker" : vm.sshUsername
        let cmd = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \(user)@\(ip)"

        // If a password is stored, copy it to clipboard so the user can paste on connect
        if let pwd = vm.sshPassword, !pwd.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pwd, forType: .string)
        }

        // Write a temp shell script and open it with Terminal.
        // This is the most reliable way to pass a command to a new Terminal window
        // without requiring AppleScript automation permission.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oven-ssh-\(vm.id.uuidString.prefix(8)).command")
        let script = "#!/bin/bash\n\(cmd)\n"
        guard (try? script.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return }
        // .command files are opened by Terminal and executed automatically
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        NSWorkspace.shared.open(tmp)
    }

    @MainActor private func pushVM(to imageRef: String, credentials: [RegistryCredential]) async {
        let tartPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        let host = imageRef.components(separatedBy: "/").first ?? ""
        let cred = credentials.first(where: { $0.registry == host })
        pushProgress = 0.0
        pushError = nil
        var errorLines: [String] = []
        AppLogger.shared.log("Pushing \(vm.name) → \(imageRef)", source: "VMDetailPane")
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartPath,
                                  registryUsername: cred?.username,
                                  registryPassword: cred?.password)
        let stream = await tartSvc.push(name: vm.name, to: imageRef)
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
                pushTask = nil
                if code == 0 {
                    AppLogger.shared.success("Push complete: \(imageRef)", source: "VMDetailPane")
                } else if !Task.isCancelled {
                    let raw = errorLines.joined(separator: "\n")
                    AppLogger.shared.error("Push failed (exit \(code)): \(raw)", source: "VMDetailPane")
                    pushError = parseTartError(raw) ?? (raw.isEmpty ? "Push failed (exit \(code))" : raw)
                }
            }
        }
    }

    @MainActor private func loadLiveConfig() async {
        let tartPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        isLoadingConfig = true
        let svc = TartService(runner: ProcessRunner(), tartPath: tartPath)
        if let config = try? await svc.get(name: vm.name) {
            liveConfig = config
        }
        isLoadingConfig = false
    }

    private func loadProfileName(id: UUID) -> String? {
        let profiles: [MDMProfile] = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [])
        return profiles.first(where: { $0.id == id })?.displayName
    }

    @MainActor
    private func revealPassword() async {
        guard let pwd = vm.sshPassword, !pwd.isEmpty else { return }
        isAuthenticating = true
        let context = LAContext()
        let name = vm.displayName.isEmpty ? vm.name : vm.displayName
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "Reveal SSH password for \(name)") { ok, _ in
                c.resume(returning: ok)
            }
        }
        if granted { revealedPassword = pwd }
        isAuthenticating = false
    }

    @MainActor
    private func checkServiceReachability() async {
        guard let ip = vm.ipAddress, !ip.isEmpty else {
            vncReachable = nil
            sshReachable = nil
            return
        }
        isCheckingPorts = true
        async let vncCheck = checkPort(ip: ip, port: 5900)
        async let sshCheck = checkPort(ip: ip, port: 22)
        let (vnc, ssh) = await (vncCheck, sshCheck)
        vncReachable = vnc
        sshReachable = ssh
        isCheckingPorts = false
    }

    private func checkPort(ip: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
                process.arguments = ["-z", "-w", "2", ip, "\(port)"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                guard (try? process.run()) != nil else {
                    continuation.resume(returning: false)
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    @MainActor
    private func lookUpEnrollment() async {
        guard canLookUpEnrollment,
              let serverID = vm.mdmServerID,
              let server = serverStore.servers.first(where: { $0.id == serverID }),
              let jamf = server.makeJamfService() else { return }
        isLookingUpEnrollment = true
        enrollmentError = nil
        do {
            enrollmentStatus = try await jamf.lookupEnrollment(serialNumber: vm.serialNumber)
            if enrollmentStatus == nil {
                enrollmentError = "Not found in \(server.friendlyName)"
            }
        } catch {
            enrollmentError = error.localizedDescription
        }
        isLookingUpEnrollment = false
    }
}

// MARK: - PortStatusDot

private struct PortStatusDot: View {
    let reachable: Bool?
    let isChecking: Bool

    var body: some View {
        Group {
            if isChecking {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
            } else if let ok = reachable {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - CopyButton

private struct CopyButton: View {
    let value: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.bordered).controlSize(.mini)
        .help("Copy to clipboard")
    }
}

// MARK: - MDMEnrollmentStatusRow

private struct MDMEnrollmentStatusRow: View {
    let vm: VirtualMachine
    let server: MDMServer?
    let status: JamfEnrollmentStatus?
    let error: String?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Enrollment")
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Look up enrollment status in \(server?.friendlyName ?? "MDM")")
                }
            }

            if let status {
                HStack(spacing: 5) {
                    Image(systemName: status.enrolled ? "checkmark.shield.fill" : "xmark.shield")
                        .foregroundStyle(status.enrolled ? (status.managed ? .green : .orange) : .red)
                        .font(.callout)
                    Text(status.summary)
                        .font(.callout)
                }
                if let name = status.deviceName, !name.isEmpty {
                    Text(name)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if status.enrolledViaADE {
                    Text("Enrolled via ADE")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let contact = status.lastContact {
                    Text("Last contact: \(contact.formatted(date: .numeric, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap \(Image(systemName: "arrow.clockwise")) to look up in \(server?.friendlyName ?? "MDM")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
