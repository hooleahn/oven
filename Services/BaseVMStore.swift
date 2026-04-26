import Foundation

@MainActor
@Observable
final class BaseVMStore: ObservableObject {

    // BaseVMStore is now a thin build/sync coordinator.
    // VM records live in VMStore — baseVMs is a computed filter.
    var vmStore: VMStore? = nil   // injected after init in OvenApp

    var baseVMs: [VirtualMachine] {
        vmStore?.vms.filter { $0.effectivelyBase } ?? []
    }

    var isBuilding = false
    var lastError: String?

    private let packerService: PackerService
    private let tartService: TartService
    private let runner: ProcessRunner
    private var activeBuildTask: Task<Void, Never>?

    init(packerService: PackerService, tartService: TartService, storageRoot: URL) {
        self.packerService = packerService
        self.tartService = tartService
        self.runner = ProcessRunner()
    }

    func add(_ vm: VirtualMachine) {
        guard let vmStore, !vmStore.vms.contains(where: { $0.name == vm.name }) else { return }
        vmStore.vms.append(vm)
        vmStore.saveToDisk()
    }

    /// Sync OCI-sourced VMs from `tart list --source OCI` into baseVMs.
    /// Sync Base VMs from tart: picks up both OCI-sourced and local base-* VMs.
    /// Safe to call on every view appear — skips already-known VMs.
    func syncOCI() async {
        // 1. OCI-sourced VMs (tart list --source OCI), deduplicated
        if let ociVMs = try? await tartService.listOCI() {
            var seen = Set<String>()
            let deduped = ociVMs.filter { info in
                if info.name.contains("@sha256:") {
                    let canonical = String(info.name.prefix(upTo: info.name.range(of: "@sha256:")!.lowerBound))
                    return !seen.contains(canonical)
                }
                let base = info.name.components(separatedBy: ":").first ?? info.name
                seen.insert(base)
                return true
            }
            for info in deduped {
                guard !baseVMs.contains(where: { $0.name == info.name }) else { continue }
                var vm = VirtualMachine(name: info.name)
                vm.isBaseVM = true
                vm.registryImageRef = info.source
                vm.osName = inferOSName(from: info.name)
                vm.vmSource = VirtualMachine.VMSource.registry
                vm.buildStatus = VirtualMachine.BuildStatus.ready
                vm.builtAt = Date()
                vm.sshUsername = "admin"
                add(vm)
            }
        }

        // 2. Locally-built base-* VMs (tart list --source local, filtered to base-*)
        if let localVMs = try? await tartService.listLocal() {
            for info in localVMs where info.name.hasPrefix("base-") {
                guard !baseVMs.contains(where: { $0.name == info.name }) else { continue }
                var vm = VirtualMachine(name: info.name, isBaseVM: true)
                vm.osName = inferOSName(from: info.name)
                vm.vmSource = VirtualMachine.VMSource.local
                vm.buildStatus = VirtualMachine.BuildStatus.ready
                vm.builtAt = Date()
                vm.sshUsername = "baker"
                add(vm)
            }
        }

        vmStore?.saveToDisk()
    }

    private func inferOSName(from name: String) -> MacOSRelease.Name {
        let lower = name.lowercased()
        if lower.contains("tahoe")    { return .tahoe }
        if lower.contains("sequoia")  { return .sequoia }
        if lower.contains("sonoma")   { return .sonoma }
        if lower.contains("ventura")  { return .ventura }
        if lower.contains("monterey") { return .monterey }
        return .sequoia
    }

    func update(id: UUID, _ apply: (inout VirtualMachine) -> Void) {
        vmStore?.update(id: id, apply)
    }

    func delete(id: UUID) async {
        guard let vm = baseVMs.first(where: { $0.id == id }) else { return }
        if vm.buildStatus == .ready || vm.buildStatus == .error {
            try? await tartService.delete(name: vm.name)
        }
        KeychainService.delete(key: vm.keychainKey)
        vmStore?.vms.removeAll { $0.id == id }
        vmStore?.saveToDisk()
        AppLogger.shared.success("Deleted base VM: \(vm.name)", source: "BaseVMStore")
    }

    func build(baseVM: VirtualMachine) async {
        // If this VM was created via the manual build path, re-use the stored config
        if let config = baseVM.manualBuildConfig {
            let bootCmd: BootCommandBlock? = config.bootCommandBlockID.flatMap { id in
                let stored: [BootCommandBlock] = AppDatabase.shared.readOrDefault(.packerBootCommands, default: [])
                return stored.first { $0.id == id }
            }
            await buildManual(baseVM: baseVM, config: config, bootCommandBlock: bootCmd)
            return
        }

        guard !isBuilding else { return }
        guard !isBuilding else { return }
        AppLogger.shared.log("Build queued: \(baseVM.name) — macOS \(baseVM.osName.rawValue) \(baseVM.osVersion)", source: "BaseVMStore")
        guard !baseVM.osVersion.isEmpty else {
            AppLogger.shared.error("Build aborted: osVersion is empty on '\(baseVM.name)'.", source: "BaseVMStore")
            lastError = "Build aborted: OS version not set."
            return
        }
        isBuilding = true; lastError = nil
        // Reset status to .building
        update(id: baseVM.id) { $0.buildStatus = .building; $0.buildLog = [] }

        activeBuildTask = Task {
            // ── Preflight checks ────────────────────────────────────────────
            let ipswAlreadyLocal = (baseVM.ipswLocalPath.map { FileManager.default.fileExists(atPath: $0) } ?? false)
                || (baseVM.ipswRemoteURL != nil && !(baseVM.ipswRemoteURL?.isEmpty ?? true))
            let preflight = await PreflightCheck.shared.runAll(baseVM: baseVM, ipswAlreadyLocal: ipswAlreadyLocal)
            if !preflight.passed {
                let msgs = preflight.failures.map { "• \($0.title): \($0.detail)" }.joined(separator: "\n")
                update(id: baseVM.id) { $0.buildStatus = .error; $0.buildLog = ["Preflight failed:\n\(msgs)"] }
                lastError = preflight.failures.first?.title ?? "Preflight check failed"
                for f in preflight.failures {
                    AppLogger.shared.error("Preflight: \(f.title) — \(f.detail)", source: "BaseVMStore")
                }
                isBuilding = false
                return
            }
            for w in preflight.warnings {
                AppLogger.shared.warning("Preflight warning: \(w)", source: "BaseVMStore")
                update(id: baseVM.id) { $0.buildLog.append("⚠️ \(w)") }
            }

            // ── Activate build session ───────────────────────────────────────
            let preventSleep = UserDefaults.standard.bool(forKey: "preventSleepDuringBuild")
            let lockInput    = UserDefaults.standard.bool(forKey: "lockInputDuringBuild")
            BuildSessionManager.shared.beginBuildSession(
                preventSleep: preventSleep,
                lockInput: lockInput
            )
            defer { BuildSessionManager.shared.endBuildSession() }

            do {
                // Resolve the IPSW path before building.
                // Priority: local file → remote URL download → auto-download via mist-cli
                var ipswPath = ""
                if let local = baseVM.ipswLocalPath,
                   FileManager.default.fileExists(atPath: local) {
                    ipswPath = local
                    AppLogger.shared.log("Using local IPSW: \(URL(fileURLWithPath: local).lastPathComponent)", source: "BaseVMStore")
                } else if let remoteURL = baseVM.ipswRemoteURL, !remoteURL.isEmpty {
                    // User supplied a direct download URL — fetch it with URLSession
                    AppLogger.shared.log("Downloading IPSW from URL: \(remoteURL)", source: "BaseVMStore")
                    update(id: baseVM.id) { $0.buildLog.append("==> Downloading IPSW from \(remoteURL)…") }
                    let settings = AppSettings.load()
                    guard let url = URL(string: remoteURL) else {
                        throw BuildError.ipswDownloadFailed("Invalid IPSW URL: \(remoteURL)")
                    }
                    let destURL = settings.ipswStorageRoot
                        .appendingPathComponent(url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        let (tmp, _) = try await URLSession.shared.download(from: url)
                        try FileManager.default.createDirectory(
                            at: settings.ipswStorageRoot, withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: tmp, to: destURL)
                    }
                    ipswPath = destURL.path
                    update(id: baseVM.id) { $0.buildLog.append("==> IPSW downloaded: \(destURL.lastPathComponent)") }
                } else {
                    let settings = AppSettings.load()
                    let ipswRoot = settings.ipswStorageRoot

                    if settings.ipswDownloadMode == .mistCli {
                        // mist-cli branch
                        try await downloadWithMistCLI(baseVM: baseVM, ipswRoot: ipswRoot,
                                                      ipswPath: &ipswPath)
                    } else {
                    // ipsw.me API branch (default) — no external tools required

                    AppLogger.shared.log("Looking up IPSW for macOS \(baseVM.osVersion) via ipsw.me…", source: "BaseVMStore")
                    update(id: baseVM.id) { $0.buildLog.append("==> Looking up IPSW for macOS \(baseVM.osVersion) via ipsw.me…") }

                    // Check if already cached locally
                    let cached = (try? FileManager.default
                        .contentsOfDirectory(at: ipswRoot, includingPropertiesForKeys: nil))?
                        .first {
                            let name = $0.lastPathComponent
                            return $0.pathExtension == "ipsw" && (
                                name == "macOS \(baseVM.osVersion).ipsw"
                                || name.contains(baseVM.osVersion.replacingOccurrences(of: ".", with: "_"))
                                || name.contains(baseVM.osVersion)
                            )
                        }

                    if let found = cached {
                        ipswPath = found.path
                        AppLogger.shared.log("Found cached IPSW: \(found.lastPathComponent)", source: "BaseVMStore")
                        update(id: baseVM.id) { $0.buildLog.append("==> Using cached IPSW: \(found.lastPathComponent)") }
                    } else {
                        let firmwares = try await IPSWService.shared.listFirmware()
                        guard let firmware = firmwares.first(where: { $0.version == baseVM.osVersion }) else {
                            let available = firmwares.prefix(5).map { $0.version }.joined(separator: ", ")
                            update(id: baseVM.id) { $0.buildLog.append("==> ERROR: macOS \(baseVM.osVersion) not found in ipsw.me. Available: \(available)…") }
                            AppLogger.shared.error("ipsw.me: version \(baseVM.osVersion) not found. Available: \(available)", source: "BaseVMStore")
                            throw BuildError.ipswDownloadFailed(baseVM.osVersion)
                        }
                        let standardName = "macOS \(baseVM.osVersion).ipsw"
                        let standardURL = ipswRoot.appendingPathComponent(standardName)
                        AppLogger.shared.log("Downloading \(firmware.displayName) (\(firmware.formattedSize))…", source: "BaseVMStore")
                        update(id: baseVM.id) { $0.buildLog.append("==> Downloading \(firmware.displayName) (\(firmware.formattedSize)) → \(standardName)") }

                        var lastPct = -1
                        // Download to standard filename directly
                        for await event in await IPSWService.shared.download(firmware, to: ipswRoot) {
                            switch event {
                            case .progress(let fraction, let written, let total):
                                let pct = Int(fraction * 100)
                                if pct / 5 > lastPct / 5 {
                                    lastPct = pct
                                    let wGB = String(format: "%.1f", Double(written) / 1_000_000_000)
                                    let tGB = String(format: "%.1f", Double(total) / 1_000_000_000)
                                    update(id: baseVM.id) { $0.buildLog.append("==> \(pct)%  \(wGB) / \(tGB) GB") }
                                    BuildMonitor.shared.ping()
                                }
                            case .completed(let url):
                                // Rename to standard filename if needed
                                let dest = url.deletingLastPathComponent().appendingPathComponent(standardName)
                                if url != dest { try? FileManager.default.moveItem(at: url, to: dest) }
                                ipswPath = dest.path
                                AppLogger.shared.success("IPSW saved: \(standardName)", source: "BaseVMStore")
                                update(id: baseVM.id) { $0.buildLog.append("==> Download complete: \(standardName)") }
                            case .failed(let error):
                                throw BuildError.ipswDownloadFailed("\(baseVM.osVersion): \(error.localizedDescription)")
                            }
                        }
                        guard !ipswPath.isEmpty else {
                            update(id: baseVM.id) { $0.buildLog.append("==> ERROR: No IPSW downloaded for macOS \(baseVM.osVersion). Check the version is available.") }
                        throw BuildError.ipswDownloadFailed(baseVM.osVersion)
                        }
                    }  // end ipsw.me branch
                    }  // end ipswDownloadMode else
                }

                // Load MDM profile if attached
                var jamfURL: String? = nil
                var invitationID: String? = nil
                let enrollmentType = "profile"
                if let profileID = baseVM.mdmProfileID {
                    let _mdmProfiles = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [MDMProfile]())
                    if !_mdmProfiles.isEmpty,
                       let profile = _mdmProfiles.first(where: { $0.id == profileID }) {
                        if let sid = profile.serverID {
                            let _mdmServers = AppDatabase.shared.readOrDefault(.mdmServers, default: [MDMServer]())
                            if let server = _mdmServers.first(where: { $0.id == sid }) {
                                jamfURL = server.serverURL.absoluteString
                            }
                        } else if !profile.customServerURL.isEmpty {
                            jamfURL = profile.customServerURL
                        }
                        invitationID = profile.invitationID.isEmpty ? nil : profile.invitationID
                    }
                }

                let config = PackerService.BuildConfig(
                    vmName: baseVM.name,
                    ipswURL: ipswPath,
                    username: baseVM.sshUsername,
                    password: baseVM.sshPassword ?? "baker",
                    cpuCount: baseVM.cpuCount,
                    memoryGB: baseVM.memoryGB,
                    diskGB: baseVM.diskGB,
                    installRosetta: baseVM.installRosetta,
                    installHomebrew: baseVM.installHomebrew,
                    enableSSHDaemon: baseVM.enableSSHDaemon,
                    enableAutoLogin: baseVM.enableAutoLogin,
                    enablePasswordlessSudo: baseVM.enablePasswordlessSudo,
                    xcodeVersion: baseVM.xcodeVersion,
                    jamfURL: jamfURL,
                    mdmInvitationID: invitationID,
                    enrollmentType: enrollmentType,
                    showGraphics: UserDefaults.standard.bool(forKey: "showGraphicsDuringBuild")
                )

                // Write default template (to defaults/ subdir) and refresh vars file.
                // Never overwrites user-edited templates in the root.
                let names = try await packerService.writeTemplate(config: config)
                let varsName = names.vars

                // Resolve which template to actually use:
                // 1. customTemplateID (v5+ UUID reference) → URL via PackerTemplateStore
                // 2. customTemplatePath (legacy v4 absolute path string)
                // 3. Auto-detect single custom template matching vm name
                // 4. Default template in defaults/ subdir
                let customOverride: URL? = {
                    if let id = baseVM.customTemplateID {
                        return PackerTemplateStore().template(id: id)?.url
                    }
                    if let path = baseVM.customTemplatePath, !path.isEmpty {
                        return URL(fileURLWithPath: path)
                    }
                    return nil
                }()
                let templateName = (try? await packerService.resolveTemplate(
                    vmName: baseVM.name,
                    customOverride: customOverride
                )) ?? names.template

                AppLogger.shared.log(
                    templateName.hasPrefix("defaults/")
                        ? "Using default template: \(templateName)"
                        : "Using custom template: \(templateName)",
                    source: "BaseVMStore"
                )

                // Resolve vars file: user-selected vars override (v5+) > generated vars
                let resolvedVarsName: String = {
                    if let id = baseVM.customVarsFileID,
                       let varsURL = PackerTemplateStore().template(id: id)?.url {
                        // Path relative to templatesRoot, or absolute if outside
                        let root = AppSettings.load().packerTemplatesRoot
                        if varsURL.path.hasPrefix(root.path) {
                            return String(varsURL.path.dropFirst(root.path.count + 1))
                        }
                        return varsURL.path
                    }
                    return varsName
                }()

                update(id: baseVM.id) {
                    $0.packerTemplateName = templateName
                    $0.packerVarsName = resolvedVarsName
                }

                let debug = UserDefaults.standard.bool(forKey: "debugModeEnabled")
                AppLogger.shared.log("Starting build: \(baseVM.name)", source: "BaseVMStore")
                await NotificationService.shared.notifyBuildStarted(vmName: baseVM.name)
                update(id: baseVM.id) { $0.buildLog.append("==> IPSW: \(ipswPath)") }
                // Always log key build parameters — critical for diagnosing failures
                AppLogger.shared.log("Build params: IPSW=\(URL(fileURLWithPath: ipswPath).lastPathComponent) template=\(templateName) vars=\(resolvedVarsName)", source: "BaseVMStore")
                update(id: baseVM.id) { $0.buildLog.append("==> OS: macOS \(baseVM.osName.rawValue) \(baseVM.osVersion)") }
                update(id: baseVM.id) { $0.buildLog.append("==> Hardware: \(baseVM.cpuCount) CPU · \(baseVM.memoryGB) GB RAM · \(baseVM.diskGB) GB disk") }
                update(id: baseVM.id) { $0.buildLog.append("==> Username: \(baseVM.sshUsername)") }
                if debug {
                    AppLogger.shared.log("[debug] IPSW storage root: \(URL(fileURLWithPath: ipswPath).deletingLastPathComponent().path)", source: "BaseVMStore")
                    AppLogger.shared.log("[debug] IPSW path: \(ipswPath)", source: "BaseVMStore")
                    AppLogger.shared.log("[debug] Template: \(templateName)", source: "BaseVMStore")
                    AppLogger.shared.log("[debug] Vars: \(resolvedVarsName)", source: "BaseVMStore")
                    AppLogger.shared.log("[debug] Templates root: \(AppSettings.load().packerTemplatesRoot.path)", source: "BaseVMStore")
                    AppLogger.shared.log("[debug] Install Rosetta: \(baseVM.installRosetta), Homebrew: \(baseVM.installHomebrew), SSH: \(baseVM.enableSSHDaemon)", source: "BaseVMStore")
                    AppLogger.shared.log("[debug] MDM profile ID: \(baseVM.mdmProfileID?.uuidString ?? "none")", source: "BaseVMStore")
                }

                // packer init + build (combined stream)
                // ── Template validation ─────────────────────────────────
                let validationResult = await PreflightCheck.shared.validateTemplate(
                    templateName: templateName, varsName: resolvedVarsName)
                if case .failure(let err) = validationResult {
                    let msg = err.localizedDescription
                    update(id: baseVM.id) { $0.buildLog.append("==> ERROR: Template validation failed") }
                    update(id: baseVM.id) { $0.buildLog.append("==> Template: \(templateName)") }
                    update(id: baseVM.id) { $0.buildLog.append("==> \(msg)") }
                    throw BuildError.templateValidationFailed(msg)
                }
                update(id: baseVM.id) { $0.buildLog.append("==> Template: \(templateName) ✓") }

                // ── Start build monitor ──────────────────────────────────────
                BuildMonitor.shared.start(
                    onTimeout: {
                        Task { @MainActor in
                            self.cancelBuild()
                            self.lastError = "Build timed out — packer was taking too long"
                            AppLogger.shared.error("Build timed out", source: "BuildMonitor")
                        }
                    },
                    onHeartbeatWarning: { minutes in
                        Task { @MainActor in
                            self.update(id: baseVM.id) {
                                $0.buildLog.append("⚠️ No output for \(minutes) minutes — build may be stuck")
                            }
                        }
                    },
                    onLowDisk: { _ in
                        Task { @MainActor in
                            self.cancelBuild()
                            self.lastError = "Build aborted: disk space critically low"
                        }
                    },
                    osName: baseVM.osName.rawValue
                )
                defer { BuildMonitor.shared.stop() }

                let stream = await packerService.buildWithInit(
                    templateName: templateName,
                    varsFileName: resolvedVarsName,
                    username: baseVM.sshUsername,
                    password: baseVM.sshPassword ?? "baker",
                    showGraphics: UserDefaults.standard.bool(forKey: "showGraphicsDuringBuild")
                )
                let buildResult = await StreamConsumer.buildLog(stream, source: "Packer") { [self] line in
                    update(id: baseVM.id) { $0.buildLog.append(line) }
                    Task { @MainActor in BuildMonitor.shared.processLogLine(line) }
                }
                if buildResult.succeeded {
                    BuildMonitor.shared.recordCompletion(
                        osName: baseVM.osName.rawValue, osVersion: baseVM.osVersion, success: true)
                    update(id: baseVM.id) { $0.buildStatus = .ready; $0.builtAt = Date() }
                    AppLogger.shared.success("Build complete: \(baseVM.name)", source: "PackerService")
                    await NotificationService.shared.notifyBuildComplete(vmName: baseVM.name, success: true)
                    BuildSessionManager.shared.performBuildCompletionAction()
                } else {
                    BuildMonitor.shared.recordCompletion(
                        osName: baseVM.osName.rawValue, osVersion: baseVM.osVersion, success: false)
                    update(id: baseVM.id) { $0.buildStatus = .error }
                    lastError = "Packer exited with code \(buildResult.exitCode)"
                    AppLogger.shared.error("Build failed (\(buildResult.exitCode)): \(baseVM.name)", source: "PackerService")
                    await NotificationService.shared.notifyBuildComplete(vmName: baseVM.name, success: false, detail: "Exit code \(buildResult.exitCode)")
                    BuildSessionManager.shared.performBuildCompletionAction()
                }
            } catch {
                update(id: baseVM.id) { $0.buildStatus = .error }
                lastError = error.localizedDescription
                AppLogger.shared.error(error.localizedDescription, source: "BaseVMStore")
                await NotificationService.shared.notifyBuildComplete(
                    vmName: baseVM.name, success: false, detail: error.localizedDescription)
                BuildSessionManager.shared.performBuildCompletionAction()
            }
            isBuilding = false
            vmStore?.saveToDisk()
        }
    }

    func cancelBuild() {
        activeBuildTask?.cancel(); activeBuildTask = nil
        if let idx = vmStore?.vms.firstIndex(where: { $0.buildStatus == .building }) {
            vmStore?.vms[idx].buildStatus = .error
        }
        isBuilding = false
        AppLogger.shared.warning("Build cancelled by user", source: "BaseVMStore")
    }

    /// Delete saved metadata and rebuild: reload local base-* VMs and re-sync OCI VMs.
    func resetMetadata() async {
        // Remove all base VMs from VMStore
        vmStore?.vms.removeAll { $0.effectivelyBase }
        vmStore?.saveToDisk()
        AppLogger.shared.log("Base VM metadata reset — rebuilding from tart list", source: "BaseVMStore")
        await syncOCI()
        // Re-discover locally built base-* VMs from tart list
        if let localVMs = try? await tartService.listLocal() {
            for info in localVMs where info.name.hasPrefix("base-") {
                guard !baseVMs.contains(where: { $0.name == info.name }) else { continue }
                var vm = VirtualMachine(name: info.name, isBaseVM: true)
                vm.osName = inferOSName(from: info.name)
                vm.vmSource = VirtualMachine.VMSource.local
                vm.buildStatus = VirtualMachine.BuildStatus.ready
                vm.builtAt = Date()
                vm.sshUsername = "baker"
                add(vm)
            }
        }
    }

    // Storage delegated to VMStore — no local disk methods needed
}



// MARK: - Manual build (generated HCL path)

extension BaseVMStore {
    /// Builds a base VM from a ManualBuildConfig by generating the HCL, writing it to
    /// a temp file, then running the same build pipeline as the template path.
    func buildManual(baseVM: VirtualMachine, config: ManualBuildConfig,
                     bootCommandBlock: BootCommandBlock?) async {
        guard !isBuilding else { return }
        AppLogger.shared.log("Manual build queued: \(baseVM.name) — macOS \(baseVM.osName.rawValue) \(baseVM.osVersion)", source: "BaseVMStore")
        guard !baseVM.osVersion.isEmpty else {
            AppLogger.shared.error("Manual build aborted: osVersion is empty on '\(baseVM.name)'.", source: "BaseVMStore")
            lastError = "Build aborted: OS version not set."
            return
        }
        isBuilding = true; lastError = nil
        update(id: baseVM.id) { $0.buildStatus = .building; $0.buildLog = [] }

        activeBuildTask = Task {
            // Preflight
            let ipswAlreadyLocal: Bool = {
                switch config.ipswSource {
                case .filePath(let u): return FileManager.default.fileExists(atPath: u.path)
                case .url:            return false
                case .auto:           return false
                }
            }()
            let preflight = await PreflightCheck.shared.runAll(baseVM: baseVM, ipswAlreadyLocal: ipswAlreadyLocal)
            if !preflight.passed {
                let msgs = preflight.failures.map { "• \($0.title): \($0.detail)" }.joined(separator: "\n")
                update(id: baseVM.id) { $0.buildStatus = .error; $0.buildLog = ["Preflight failed:\n\(msgs)"] }
                lastError = preflight.failures.first?.title ?? "Preflight check failed"
                isBuilding = false; return
            }
            for w in preflight.warnings {
                update(id: baseVM.id) { $0.buildLog.append("⚠️ \(w)") }
            }

            let preventSleep = UserDefaults.standard.bool(forKey: "preventSleepDuringBuild")
            let lockInput    = UserDefaults.standard.bool(forKey: "lockInputDuringBuild")
            BuildSessionManager.shared.beginBuildSession(preventSleep: preventSleep, lockInput: lockInput)
            defer { BuildSessionManager.shared.endBuildSession() }

            do {
                // Resolve IPSW path
                var ipswPath = ""
                switch config.ipswSource {
                case .filePath(let u):
                    ipswPath = u.path
                    AppLogger.shared.log("Using local IPSW: \(u.lastPathComponent)", source: "BaseVMStore")
                case .url(let s):
                    guard let url = URL(string: s) else {
                        throw BuildError.ipswDownloadFailed("Invalid IPSW URL: \(s)")
                    }
                    let settings = AppSettings.load()
                    let destURL = settings.ipswStorageRoot.appendingPathComponent(url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        update(id: baseVM.id) { $0.buildLog.append("==> Downloading IPSW from \(s)…") }
                        let (tmp, _) = try await URLSession.shared.download(from: url)
                        try FileManager.default.createDirectory(at: settings.ipswStorageRoot, withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: tmp, to: destURL)
                    }
                    ipswPath = destURL.path
                    update(id: baseVM.id) { $0.buildLog.append("==> IPSW downloaded: \(destURL.lastPathComponent)") }
                case .auto:
                    // Same auto-download logic as the template path
                    let settings = AppSettings.load()
                    let ipswRoot = settings.ipswStorageRoot
                    if settings.ipswDownloadMode == .mistCli {
                        try await downloadWithMistCLI(baseVM: baseVM, ipswRoot: ipswRoot, ipswPath: &ipswPath)
                    } else {
                        update(id: baseVM.id) { $0.buildLog.append("==> Looking up IPSW for macOS \(baseVM.osVersion) via ipsw.me…") }
                        let cached = (try? FileManager.default.contentsOfDirectory(at: ipswRoot, includingPropertiesForKeys: nil))?
                            .first { $0.pathExtension == "ipsw" && $0.lastPathComponent.contains(baseVM.osVersion) }
                        if let found = cached {
                            ipswPath = found.path
                            update(id: baseVM.id) { $0.buildLog.append("==> Using cached IPSW: \(found.lastPathComponent)") }
                        } else {
                            let firmwares = try await IPSWService.shared.listFirmware()
                            guard let firmware = firmwares.first(where: { $0.version == baseVM.osVersion }) else {
                                throw BuildError.ipswDownloadFailed(baseVM.osVersion)
                            }
                            let standardName = "macOS \(baseVM.osVersion).ipsw"
                            update(id: baseVM.id) { $0.buildLog.append("==> Downloading \(firmware.displayName) (\(firmware.formattedSize)) → \(standardName)") }
                            var lastPct = -1
                            for await event in await IPSWService.shared.download(firmware, to: ipswRoot) {
                                switch event {
                                case .progress(let fraction, let written, let total):
                                    let pct = Int(fraction * 100)
                                    if pct / 5 > lastPct / 5 {
                                        lastPct = pct
                                        let wGB = String(format: "%.1f", Double(written) / 1_000_000_000)
                                        let tGB = String(format: "%.1f", Double(total) / 1_000_000_000)
                                        update(id: baseVM.id) { $0.buildLog.append("==> \(pct)%  \(wGB) / \(tGB) GB") }
                                        BuildMonitor.shared.ping()
                                    }
                                case .completed(let url):
                                    let dest = url.deletingLastPathComponent().appendingPathComponent(standardName)
                                    if url != dest { try? FileManager.default.moveItem(at: url, to: dest) }
                                    ipswPath = dest.path
                                    update(id: baseVM.id) { $0.buildLog.append("==> Download complete: \(standardName)") }
                                case .failed(let error):
                                    throw BuildError.ipswDownloadFailed("\(baseVM.osVersion): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }

                AppLogger.shared.log("Starting manual build: \(baseVM.name)", source: "BaseVMStore")
                await NotificationService.shared.notifyBuildStarted(vmName: baseVM.name)
                update(id: baseVM.id) { $0.buildLog.append("==> IPSW: \(ipswPath)") }
                update(id: baseVM.id) { $0.buildLog.append("==> OS: macOS \(baseVM.osName.rawValue) \(baseVM.osVersion)") }
                update(id: baseVM.id) { $0.buildLog.append("==> Hardware: \(config.cpuCount) CPU · \(config.memoryGB) GB RAM · \(config.diskGB) GB disk") }

                BuildMonitor.shared.start(
                    onTimeout: {
                        Task { @MainActor in
                            self.cancelBuild()
                            self.lastError = "Build timed out — tart was taking too long"
                        }
                    },
                    onHeartbeatWarning: { minutes in
                        Task { @MainActor in
                            self.update(id: baseVM.id) {
                                $0.buildLog.append("⚠️ No output for \(minutes) minutes — build may be stuck")
                            }
                        }
                    },
                    onLowDisk: { _ in
                        Task { @MainActor in
                            self.cancelBuild()
                            self.lastError = "Build aborted: disk space critically low"
                        }
                    },
                    osName: baseVM.osName.rawValue
                )
                defer { BuildMonitor.shared.stop() }

                let buildSucceeded: Bool

                if !config.automateSetupAssistant {
                    // ── Simple path: tart create directly from IPSW ─────────────────
                    // No boot command / Setup Assistant automation needed.
                    update(id: baseVM.id) { $0.buildLog.append("==> Creating VM with tart (no automation)") }
                    let stream = await tartService.create(
                        name: baseVM.name,
                        fromIPSW: ipswPath,
                        diskGB: config.diskGB
                    )
                    let result = await StreamConsumer.buildLog(stream, source: "Tart") { [self] line in
                        update(id: baseVM.id) { $0.buildLog.append(line) }
                        Task { @MainActor in BuildMonitor.shared.processLogLine(line) }
                    }
                    buildSucceeded = result.succeeded
                    if !buildSucceeded {
                        lastError = "tart exited with code \(result.exitCode)"
                        AppLogger.shared.error("tart create failed (\(result.exitCode)): \(baseVM.name)", source: "BaseVMStore")
                    }
                } else {
                    // ── Full path: generate HCL, run Packer ─────────────────────────
                    // Resolve MDM profile if configured
                    var resolvedJamfURL: String? = nil
                    var resolvedMDMInvitationID: String? = nil
                    if let profileID = config.mdmProfileID {
                        let mdmProfiles = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [MDMProfile]())
                        if let profile = mdmProfiles.first(where: { $0.id == profileID }) {
                            if let sid = profile.serverID {
                                let mdmServers = AppDatabase.shared.readOrDefault(.mdmServers, default: [MDMServer]())
                                if let server = mdmServers.first(where: { $0.id == sid }) {
                                    resolvedJamfURL = server.serverURL.absoluteString
                                }
                            } else if !profile.customServerURL.isEmpty {
                                resolvedJamfURL = profile.customServerURL
                            }
                            resolvedMDMInvitationID = profile.invitationID.isEmpty ? nil : profile.invitationID
                        }
                    }

                    let hclContent = ManualBuildHCLGenerator.generate(
                        config: config,
                        bootCommand: bootCommandBlock,
                        resolvedIPSW: ipswPath,
                        jamfURL: resolvedJamfURL,
                        mdmInvitationID: resolvedMDMInvitationID
                    )
                    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    let hclURL = tempDir.appendingPathComponent("oven-manual-\(UUID().uuidString).pkr.hcl")
                    try hclContent.write(to: hclURL, atomically: true, encoding: .utf8)
                    defer { try? FileManager.default.removeItem(at: hclURL) }

                    update(id: baseVM.id) {
                        $0.packerTemplateName = hclURL.lastPathComponent
                        $0.packerVarsName = ""
                    }

                    let debug = UserDefaults.standard.bool(forKey: "debugModeEnabled")
                    if debug {
                        AppLogger.shared.log("[debug] Generated HCL: \(hclURL.path)", source: "BaseVMStore")
                    }

                    let stream = await packerService.buildWithInitURL(
                        templateURL: hclURL,
                        username: config.credentials.username,
                        password: config.credentials.password,
                        showGraphics: UserDefaults.standard.bool(forKey: "showGraphicsDuringBuild")
                    )
                    let buildResult = await StreamConsumer.buildLog(stream, source: "Packer") { [self] line in
                        update(id: baseVM.id) { $0.buildLog.append(line) }
                        Task { @MainActor in BuildMonitor.shared.processLogLine(line) }
                    }
                    buildSucceeded = buildResult.succeeded
                    if !buildSucceeded {
                        lastError = "Packer exited with code \(buildResult.exitCode)"
                        AppLogger.shared.error("Manual build failed (\(buildResult.exitCode)): \(baseVM.name)", source: "PackerService")
                    }
                }

                BuildMonitor.shared.recordCompletion(
                    osName: baseVM.osName.rawValue, osVersion: baseVM.osVersion, success: buildSucceeded)

                if buildSucceeded {
                    update(id: baseVM.id) { $0.buildStatus = .ready; $0.builtAt = Date() }
                    AppLogger.shared.success("Manual build complete: \(baseVM.name)", source: "BaseVMStore")
                    await NotificationService.shared.notifyBuildComplete(vmName: baseVM.name, success: true)
                    BuildSessionManager.shared.performBuildCompletionAction()
                } else {
                    update(id: baseVM.id) { $0.buildStatus = .error }
                    await NotificationService.shared.notifyBuildComplete(vmName: baseVM.name, success: false, detail: lastError ?? "Build failed")
                    BuildSessionManager.shared.performBuildCompletionAction()
                }
            } catch {
                update(id: baseVM.id) { $0.buildStatus = .error }
                lastError = error.localizedDescription
                AppLogger.shared.error(error.localizedDescription, source: "BaseVMStore")
                await NotificationService.shared.notifyBuildComplete(
                    vmName: baseVM.name, success: false, detail: error.localizedDescription)
                BuildSessionManager.shared.performBuildCompletionAction()
            }
            isBuilding = false
            vmStore?.saveToDisk()
        }
    }
}

// MARK: - mist-cli download helper

extension BaseVMStore {
    func downloadWithMistCLI(baseVM: VirtualMachine, ipswRoot: URL,
                             ipswPath: inout String) async throws {
        AppLogger.shared.log("Downloading macOS \(baseVM.osVersion) via mist-cli…", source: "BaseVMStore")
        update(id: baseVM.id) { $0.buildLog.append("==> Downloading macOS \(baseVM.osVersion) IPSW via mist-cli…") }

        // Resolution: system mist → managed mist → auto-download managed copy
        let managedMist = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/mist-cli").path
        let mistPath: String
        let (whichOut, _) = (try? await ProcessRunner().run("/usr/bin/which", arguments: ["mist"])) ?? ("", "")
        let sysMist = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sysMist.isEmpty {
            mistPath = sysMist
            AppLogger.shared.log("Using system mist at \(sysMist)", source: "BaseVMStore")
        } else if FileManager.default.fileExists(atPath: managedMist) {
            mistPath = managedMist
            AppLogger.shared.log("Using managed mist-cli", source: "BaseVMStore")
        } else {
            // Auto-install managed mist-cli via GitHub releases
            AppLogger.shared.log("mist-cli not found — downloading managed copy…", source: "BaseVMStore")
            update(id: baseVM.id) { $0.buildLog.append("==> Installing mist-cli…") }
            do {
                try await installManagedMistCLI(to: URL(fileURLWithPath: managedMist).deletingLastPathComponent())
            } catch {
                throw BuildError.ipswDownloadFailed(
                    "mist-cli not found and auto-install failed (\(error.localizedDescription)). " +
                    "Go to Preferences → Build and switch to 'ipsw.me' download mode, or install mist-cli manually."
                )
            }
            mistPath = managedMist
        }

        // Check local cache
        let cached = (try? FileManager.default
            .contentsOfDirectory(at: ipswRoot, includingPropertiesForKeys: nil))?
            .first {
                let name = $0.lastPathComponent
                return $0.pathExtension == "ipsw" && (
                    name == "macOS \(baseVM.osVersion).ipsw"
                    || name.contains(baseVM.osVersion.replacingOccurrences(of: ".", with: "_"))
                    || name.contains(baseVM.osVersion)
                )
            }
        if let found = cached {
            ipswPath = found.path
            update(id: baseVM.id) { $0.buildLog.append("==> Using cached IPSW: \(found.lastPathComponent)") }
            return
        }

        let svc = MistService(runner: ProcessRunner(), mistPath: mistPath, ipswRoot: ipswRoot)
        let (dlStream, expectedURL) = await svc.downloadFirmwareByVersion(baseVM.osVersion)
        let dlResult = await StreamConsumer.buildLog(dlStream, source: "mist") { [self] line in
            update(id: baseVM.id) { $0.buildLog.append(line) }
        }
        guard dlResult.succeeded, FileManager.default.fileExists(atPath: expectedURL.path) else {
            throw BuildError.ipswDownloadFailed(baseVM.osVersion)
        }
        ipswPath = expectedURL.path
        AppLogger.shared.success("IPSW downloaded: \(expectedURL.lastPathComponent)", source: "BaseVMStore")
    }

    private func installManagedMistCLI(to directory: URL) async throws {
        // Fetch latest release tag from GitHub
        let tagURL = URL(string: "https://api.github.com/repos/ninxsoft/mist-cli/releases/latest")!
        let (tagData, _) = try await URLSession.shared.data(from: tagURL)
        struct Release: Decodable { let tag_name: String }
        let release = try JSONDecoder().decode(Release.self, from: tagData)
        let tag = release.tag_name
        let pkgName = "mist-cli-\(tag).pkg"
        let pkgURL = URL(string: "https://github.com/ninxsoft/mist-cli/releases/download/\(tag)/\(pkgName)")!

        let (tmp, _) = try await URLSession.shared.download(from: pkgURL)
        let dest = directory.appendingPathComponent(pkgName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)

        // Install the pkg
        let runner = ProcessRunner()
        try await runner.run("/usr/sbin/installer", arguments: ["-pkg", dest.path, "-target", "/"])
        AppLogger.shared.success("mist-cli \(tag) installed", source: "BaseVMStore")
    }
}

// MARK: - Build errors

enum BuildError: LocalizedError {
    case ipswDownloadFailed(String)
    case templateValidationFailed(String)

    var errorDescription: String? {
        switch self {
        case .ipswDownloadFailed(let version):
            return "Failed to download IPSW for macOS \(version). Check your internet connection."
        case .templateValidationFailed(let msg):
            return "Packer template validation failed: \(msg)"
        }
    }
}
