import SwiftUI
import AppKit


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
    @State private var liveConfig: TartService.TartVMConfig? = nil
    @State private var isLoadingConfig = false
    @State private var confirmStop: VirtualMachine? = nil

    // MDM enrollment status
    @State private var enrollmentStatus: JamfEnrollmentStatus? = nil
    @State private var enrollmentError: String? = nil
    @State private var isLookingUpEnrollment = false

    /// True when serial number is long enough and an MDM server is linked
    private var canLookUpEnrollment: Bool {
        vm.serialNumber.count >= 10 && vm.mdmServerID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
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
                                .buttonStyle(.plain)
                                .help("Refresh from tart")
                            }
                        }
                        .padding(.horizontal, 14)
                        let cpu = liveConfig?.cpu.map { "\($0) vCPU" } ?? "\(vm.cpuCount) vCPU"
                        let mem = liveConfig?.memory.map { "\($0 / 1024) GB" } ?? "\(vm.memoryGB) GB"
                        let diskMax = liveConfig?.disk.map { "\($0) GB" } ?? "\(vm.diskGB) GB"
                        let disk = vm.actualDiskGB.map { "\(diskMax) max · \($0) GB used" } ?? diskMax
                        DetailRow("CPU", cpu)
                        DetailRow("Memory", mem)
                        DetailRow("Disk", disk)
                        DetailRow("macOS", vm.macOSVersion.isEmpty ? "—" : vm.macOSVersion)
                        if let display = liveConfig?.display {
                            DetailRow("Display", display)
                        }
                        DetailRow("S/N", vm.serialNumber.isEmpty ? "—" : vm.serialNumber)
                    }
                    DetailSection("Network") {
                        DetailRow("IP Address", vm.ipAddress ?? "—", monospaced: true, copyable: vm.ipAddress != nil)
                        if let ip = vm.ipAddress, !ip.isEmpty {
                            let vncURL = "vnc://\(ip)"
                            DetailRow("VNC", vncURL, monospaced: true, copyable: true)
                            HStack {
                                Spacer()
                                Button("Open VNC…") {
                                    NSWorkspace.shared.open(URL(string: vncURL)!)
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                .padding(.horizontal, 14).padding(.bottom, 4)
                            }
                        }
                        DetailRow("SSH", "Port 22")
                        if !vm.sshUsername.isEmpty {
                            DetailRow("Username", vm.sshUsername, monospaced: true, copyable: true)
                        }
                        if vm.sshPassword != nil {
                            DetailRow("Password", "stored in Keychain")
                        }
                    }
                    DetailSection("Identity & Dates") {
                        if !vm.description.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Description")
                                    .font(.caption).fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                Text(vm.description)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                        }
                        if !vm.displayName.isEmpty && vm.displayName != vm.name {
                            DetailRow("Display name", vm.displayName)
                        }
                        DetailRow("Tart name", vm.name, monospaced: true, copyable: true)
                        DetailRow("Created", vm.createdAt.formatted(date: .abbreviated, time: .omitted))
                        DetailRow("Last started", vm.lastStartedAt.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "Never")
                        if !vm.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tags")
                                    .font(.caption).fontWeight(.medium)
                                    .foregroundStyle(.secondary).textCase(.uppercase)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(Array(vm.tags.enumerated()), id: \.offset) { _, tag in TagChip(tag: tag) }
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                        }
                    }
                    // Origin: base VM it was cloned from
                    if let baseID = vm.baseVMID,
                       let baseVM = baseVMStore.baseVMs.first(where: { $0.id == baseID }) {
                        DetailSection("Origin") {
                            DetailRow("Base VM", baseVM.name)
                            DetailRow("macOS", "\(baseVM.osName.rawValue) \(baseVM.osVersion)")
                        }
                    }
                    // MDM enrollment
                    if theme.mdmEnabled && (vm.mdmProfileID != nil || vm.mdmServerID != nil || canLookUpEnrollment) {
                        DetailSection("MDM") {
                            if let serverID = vm.mdmServerID,
                               let server = serverStore.servers.first(where: { $0.id == serverID }) {
                                DetailRow("Server", server.friendlyName)
                            }
                            if let profileID = vm.mdmProfileID {
                                let profileName = loadProfileName(id: profileID)
                                if let name = profileName {
                                    DetailRow("Profile", name)
                                }
                            }
                            // Enrollment status lookup (requires serial number ≥ 10 chars + MDM server)
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
                        DetailSection("Registry") {
                            DetailRow("Image", ref)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()
            actionsSection
            .padding(12)
        }
        .background(.windowBackground)
        .sheet(isPresented: $isPresentingPushSheet) {
            PushToRegistrySheet(vmName: vm.name) { imageRef, credentials in
                isPresentingPushSheet = false
                Task { await pushVM(to: imageRef, credentials: credentials) }
            }
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
            // Start IP polling immediately when detail pane opens for a running VM
            if vm.status == .running && (vm.ipAddress == nil || vm.ipAddress?.isEmpty == true) {
                await vmStore.refreshIP(for: vm)
            }
            await loadLiveConfig()
            // Auto-look up enrollment status if eligible
            if canLookUpEnrollment {
                await lookUpEnrollment()
            }
        }
        .onChange(of: vm.status) { _, newStatus in
            if newStatus == .running && vm.ipAddress == nil {
                Task { await vmStore.refreshIP(for: vm) }
            }
        }
    }


    // MARK: - Subviews

    @ViewBuilder private var headerSection: some View {
        VStack(spacing: 4) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
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
        .padding(14)
        .background(.bar)
    }


    @ViewBuilder private var actionsSection: some View {
        Divider()
        VStack(spacing: 6) {
                VStack(spacing: 6) {
                    if vm.status == .running {
                        Button {
                            openSSH(vm: vm)
                        } label: {
                            Label("Open SSH in Terminal", systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(vm.ipAddress == nil)
    
                        Button {
                            Task { await vmStore.refreshIP(for: vm) }
                        } label: {
                            HStack(spacing: 6) {
                                if vm.isResolvingIP {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(vm.ipAddress.map { $0.isEmpty ? "Resolving IP…" : $0 } ?? "Resolving IP…")
                                    .font(.system(.callout, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(vm.isResolvingIP)
                    }
    
                    if vm.status == .running || vm.status == .suspended {
                        Button {
                            if !vm.isStopping { confirmStop = vm }
                        } label: {
                            if vm.isStopping {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Stopping…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Label("Stop VM", systemImage: "stop.fill").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.regular).tint(.red)
                        .disabled(vm.isStopping)
                    } else if vm.status == .stopped {
                        Button {
                            onStart()
                        } label: {
                            Label("Start VM", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
    
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
                            .buttonStyle(.bordered).controlSize(.regular)
                        }
                    }
    
                    if let err = pushError {
                        Label(err, systemImage: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                            .lineLimit(3)
                    }
                }
    }
    }

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
                if code == 0 {
                    AppLogger.shared.success("Push complete: \(imageRef)", source: "VMDetailPane")
                } else {
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
        _ = AppSettings.defaultLocalStorageRoot
        let profiles = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [MDMProfile]())
        guard !profiles.isEmpty || true
        else { return nil }
        return profiles.first(where: { $0.id == id })?.name
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
                    Text("Last contact: \(contact.formatted(date: .abbreviated, time: .shortened))")
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
