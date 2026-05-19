import Foundation

// MARK: - VMStore errors

enum VMStoreError: LocalizedError {
    case vmNotFound(String)
    case nameAlreadyExists(String)
    case tartServiceUnavailable

    var errorDescription: String? {
        switch self {
        case .vmNotFound(let name):       return "VM '\(name)' not found."
        case .nameAlreadyExists(let n):   return "A VM named '\(n)' already exists."
        case .tartServiceUnavailable:     return "tart is not installed or not ready."
        }
    }
}

// MARK: - VMStore

/// Single source of truth for all VirtualMachine records.
///
/// Responsibilities:
///   1. Persist Oven metadata (displayName, tags, description, etc.) as JSON.
///   2. Sync with `tart list` to pick up status changes and VMs added outside Oven.
///   3. Delegate all tart operations to TartService.
@MainActor
@Observable
final class VMStore: ObservableObject {

    // MARK: Published state

    var vms: [VirtualMachine] = []
    var isSyncing = false
    var lastError: String?

    // MARK: Dependencies

    private let tartService: TartService
    private let metadataURL: URL

    // MARK: Init

    init(tartService: TartService, storageRoot: URL) {
        self.tartService = tartService
        self.metadataURL = storageRoot
            .appendingPathComponent("vms", isDirectory: true)
            .appendingPathComponent("metadata.json")
        loadFromDisk()
    }

    // MARK: - Sync with tart

    /// Refresh the VM list by calling `tart list` and merging results with
    /// persisted metadata. Call on app launch and after any mutating operation.
    func sync() async {
        // Fetch off-main to avoid blocking the UI
        let tartVMs: [TartVMInfo]
        do {
            tartVMs = try await tartService.listLocal()
        } catch {
            lastError = error.localizedDescription
            AppLogger.shared.error("Sync failed: \(error.localizedDescription)", source: "VMStore")
            return
        }

        // Apply all mutations in one pass — set isSyncing only around the merge
        isSyncing = true
        mergeWithTart(tartVMs)
        saveToDisk()
        isSyncing = false
        AppLogger.shared.log("Synced \(tartVMs.count) VMs from tart", source: "VMStore")
    }

    /// Refresh the IP address for a single running VM.
    /// Polls for the VM's IP address, retrying every 3 s for up to 90 s.
    /// Returns immediately if the IP is already known or the VM is not running.
    func refreshIP(for vm: VirtualMachine) async {
        guard vm.status == .running else { return }
        // Already have it — nothing to do
        if let existing = vms.first(where: { $0.id == vm.id })?.ipAddress,
           !existing.isEmpty { return }
        // Bail if another caller is already polling for this VM's IP
        guard vms.first(where: { $0.id == vm.id })?.isResolvingIP != true else { return }

        update(id: vm.id) { $0.isResolvingIP = true }
        defer { update(id: vm.id) { $0.isResolvingIP = false } }

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            // Stop if VM is no longer running
            guard vms.first(where: { $0.id == vm.id })?.status == .running else { break }
            do {
                // waitSeconds: 1 — let tart fail fast; sleep below handles the 3-s cadence
                let ip = try await tartService.ip(name: vm.name, waitSeconds: 1)
                if !ip.isEmpty {
                    update(id: vm.id) { $0.ipAddress = ip; $0.isResolvingIP = false }
                    saveToDisk()
                    return
                }
            } catch {
                // tart ip returned non-zero — VM not ready yet, keep polling
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: - CRUD

    /// Register a new VM record (call after `tart clone` succeeds).
    func register(_ vm: VirtualMachine) {
        guard !vms.contains(where: { $0.name == vm.name }) else { return }
        vms.append(vm)
        saveToDisk()
    }

    /// Clone a base VM into a new VM. Runs the tart clone operation then registers the result.
    func clone(
        source: String,
        newName: String,
        displayName: String? = nil,
        description: String = "",
        tags: [String] = [],
        macOSVersion: String = "",
        baseVMID: UUID? = nil,
        mdmProfileID: UUID? = nil,
        cpuCount: Int = 4,
        memoryGB: Int = 8,
        diskGB: Int = 80,
        registryImageRef: String? = nil,
        mdmServerID: UUID? = nil,
        sshUsername: String = "baker"
    ) async throws {
        guard !vms.contains(where: { $0.name == newName }) else {
            throw VMStoreError.nameAlreadyExists(newName)
        }

        // Optimistically add a building entry so the UI shows progress
        let placeholder = VirtualMachine(
            name: newName,
            displayName: displayName ?? newName,
            description: description,
            tags: tags,
            status: .building,
            baseVMID: baseVMID,
            mdmProfileID: mdmProfileID,
            cpuCount: cpuCount,
            memoryGB: memoryGB,
            diskGB: diskGB,
            macOSVersion: macOSVersion,
            registryImageRef: registryImageRef,
            mdmServerID: mdmServerID,
            sshUsername: sshUsername
        )
        vms.append(placeholder)
        saveToDisk()

        do {
            try await tartService.clone(source: source, destination: newName)

            // Randomise serial number, MAC address and refit display — always,
            // to avoid duplicate identifiers across cloned VMs
            try await tartService.set(
                name: newName,
                cpu: cpuCount != 4 ? cpuCount : nil,
                memoryGB: memoryGB != 8 ? memoryGB : nil,
                diskGB: diskGB != 80 ? diskGB : nil,
                randomSerial: true,
                randomMAC: true,
                displayRefit: true
            )

            update(id: placeholder.id) { $0.status = .stopped }
            saveToDisk()
        } catch {
            // Remove the placeholder on failure
            vms.removeAll { $0.id == placeholder.id }
            saveToDisk()
            throw error
        }
    }

    /// Start a VM. Returns an AsyncStream of log lines for the caller to display.
    func start(vm: VirtualMachine, mode: TartService.RunMode = .native) async -> AsyncStream<ProcessEvent> {
        update(id: vm.id) { $0.status = .running; $0.lastStartedAt = Date() }
        saveToDisk()
        return await tartService.run(name: vm.name, mode: mode, sharedFolders: vm.sharedFolders)
    }

    /// Stop a running VM.
    func stop(vm: VirtualMachine) async throws {
        update(id: vm.id) { $0.isStopping = true }
        defer { update(id: vm.id) { $0.isStopping = false } }
        try await tartService.stop(name: vm.name)
        update(id: vm.id) { $0.status = .stopped; $0.ipAddress = nil; $0.isStopping = false }
        saveToDisk()
    }

    /// Suspend a running VM.
    func suspend(vm: VirtualMachine) async throws {
        try await tartService.suspend(name: vm.name)
        update(id: vm.id) { $0.status = .suspended }
        saveToDisk()
    }

    /// Rename a VM in tart and update its metadata record.
    /// Rename a VM in tart and update its metadata record.
    func rename(vm: VirtualMachine, to newName: String) async throws {
        guard !vms.contains(where: { $0.name == newName && $0.id != vm.id }) else {
            throw VMStoreError.nameAlreadyExists(newName)
        }
        try await tartService.rename(name: vm.name, to: newName)
        update(id: vm.id) { $0.name = newName }
        saveToDisk()
        AppLogger.shared.success("Renamed VM: \(vm.name) → \(newName)", source: "VMStore")
    }

    /// Delete a VM from tart and remove its metadata record.
    func delete(vm: VirtualMachine) async throws {
        do {
            try await tartService.delete(name: vm.name)
        } catch {
            // VM may have already been removed externally (e.g. `tart remove`); still clean up metadata.
            AppLogger.shared.warning("tart delete failed for \(vm.name): \(error.localizedDescription)", source: "VMStore")
        }
        vms.removeAll { $0.id == vm.id }
        saveToDisk()
        AppLogger.shared.success("Deleted VM: \(vm.name)", source: "VMStore")
    }

    /// Update mutable metadata (displayName, tags, description, etc.).
    func updateMetadata(id: UUID, _ apply: (inout VirtualMachine) -> Void) {
        update(id: id, apply)
        saveToDisk()
    }

    // MARK: - Queries

    func vm(named name: String) -> VirtualMachine? {
        vms.first { $0.name == name }
    }

    func vm(id: UUID) -> VirtualMachine? {
        vms.first { $0.id == id }
    }

    func vms(withTag tag: String) -> [VirtualMachine] {
        vms.filter { $0.tags.contains(tag) }
    }

    var allTags: [String] {
        Array(Set(vms.flatMap(\.tags))).sorted()
    }

    var runningVMs: [VirtualMachine] {
        vms.filter { $0.status == .running }
    }

    // MARK: - Private helpers

    func update(id: UUID, _ apply: (inout VirtualMachine) -> Void) {
        guard let idx = vms.firstIndex(where: { $0.id == id }) else { return }
        apply(&vms[idx])
    }

    /// Merge tart list output into our records:
    /// - Update status for existing records
    /// - Add new records for VMs we don't know about (created outside Oven)
    /// - Do NOT remove records tart no longer lists — they may be on an
    ///   external drive that isn't mounted; let the user delete explicitly.
    private func mergeWithTart(_ tartVMs: [TartVMInfo]) {
        // Keep base-* VMs in VMStore but mark them as base.
        // They will show in Base VM view via effectivelyBase.
        // Remove only OCI-sourced VMs (managed by BaseVMStore).
        vms.removeAll { $0.name.hasPrefix("base-") && !$0.isBaseVM }

        // All local VMs are included; effectivelyBase drives which view shows them.
        let filteredVMs = tartVMs
        var knownNames = Set(vms.map(\.name))

        for info in filteredVMs {
            if let idx = vms.firstIndex(where: { $0.name == info.name }) {
                // Existing VM — update mutable tart state but PRESERVE all Oven metadata
                // Clear stale registryImageRef for local VMs (was incorrectly set from info.source)
                if !vms[idx].name.contains("/") { vms[idx].registryImageRef = nil }
                // Base VMs present in tart list are by definition built — fix stale notBuilt status
                if vms[idx].isBaseVM && vms[idx].buildStatus == .notBuilt {
                    vms[idx].buildStatus = .ready
                }
                vms[idx].status = VirtualMachine.Status(tartState: info.state)
                if let sz = info.size { vms[idx].actualDiskGB = sz }
                if vms[idx].macOSVersion.isEmpty {
                    vms[idx].macOSVersion = inferMacOSVersion(from: info.name)
                }
                if vms[idx].osName == .unknown {
                    let (inferred, ver) = inferOSRelease(from: info.name)
                    if inferred != .unknown {
                        vms[idx].osName = inferred
                        if vms[idx].osVersion.isEmpty { vms[idx].osVersion = ver }
                    }
                }
                // Refresh createdAt from filesystem
                let fsDate = vmCreationDate(name: info.name)
                if fsDate < vms[idx].createdAt { vms[idx].createdAt = fsDate }
                // Sync lastStartedAt from disk.img modification date — catches
                // VMs started externally (e.g. via `tart run` in Terminal)
                if let diskDate = vmLastStartedDate(name: info.name) {
                    if vms[idx].lastStartedAt == nil || diskDate > vms[idx].lastStartedAt! {
                        vms[idx].lastStartedAt = diskDate
                    }
                }
            } else {
                // Unknown to Oven — add with inferred metadata
                var vm = VirtualMachine(fromTart: info)
                vm.actualDiskGB = info.size
                vm.createdAt = vmCreationDate(name: info.name)
                vm.macOSVersion = inferMacOSVersion(from: info.name)
                let (inferred, ver) = inferOSRelease(from: info.name)
                if inferred != .unknown { vm.osName = inferred; vm.osVersion = ver }
                if info.name.hasPrefix("base-") {
                    vm.isBaseVM = true
                    vm.buildStatus = .ready  // exists in tart = already built
                }
                vms.append(vm)
                knownNames.insert(info.name)
            }
        }

        // Remove VMs from our list that tart no longer knows about
        // (only remove non-base VMs we added, not ones still building)
        let tartNames = Set(filteredVMs.map(\.name))

        for idx in vms.indices {
            if !tartNames.contains(vms[idx].name) && vms[idx].status == .running {
                vms[idx].status = .stopped
            }
        }
    }

    // MARK: - Metadata inference

    /// Returns the inferred `MacOSRelease.Name` and dotted version string from a VM name.
    /// e.g. "base-sequoia-15-6-1-nomdm" → (.sequoia, "15.6.1")
    private func inferOSRelease(from name: String) -> (MacOSRelease.Name, String) {
        let bare = name.components(separatedBy: "/").last ?? name
        let lower = bare.lowercased()
        let osName: MacOSRelease.Name
        if lower.contains("tahoe")         { osName = .tahoe }
        else if lower.contains("sequoia")  { osName = .sequoia }
        else if lower.contains("sonoma")   { osName = .sonoma }
        else if lower.contains("ventura")  { osName = .ventura }
        else if lower.contains("monterey") { osName = .monterey }
        else { return (.unknown, "") }
        let versionPattern = #"(\d+[-\.]\d+(?:[-\.]\d+)?)"#
        let ver = bare.range(of: versionPattern, options: .regularExpression)
            .map { bare[$0].replacingOccurrences(of: "-", with: ".") } ?? ""
        return (osName, ver)
    }

    /// Infer display string from VM name e.g. "sequoia-15-6-1-nomdm-abc" → "macOS Sequoia 15.6.1"
    private func inferMacOSVersion(from name: String) -> String {
        let (osName, ver) = inferOSRelease(from: name)
        guard osName != .unknown else { return "" }
        return ver.isEmpty ? "macOS \(osName.rawValue)" : "macOS \(osName.rawValue) \(ver)"
    }
    private func vmCreationDate(name: String) -> Date {
        let tartHome = AppSettings.load().resolvedTartHome
        let vmDir = tartHome.appendingPathComponent("vms/\(name)")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: vmDir.path),
              let created = attrs[.creationDate] as? Date
        else { return Date() }
        return created
    }

    /// Infers the last time a VM was started from the modification date of its
    /// disk image — tart updates disk.img whenever the VM runs.
    private func vmLastStartedDate(name: String) -> Date? {
        let tartHome = AppSettings.load().resolvedTartHome
        let diskImg = tartHome.appendingPathComponent("vms/\(name)/disk.img")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: diskImg.path),
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        // Only trust this if it's after the VM's creation date (rules out the initial write)
        let created = vmCreationDate(name: name)
        return modified > created ? modified : nil
    }

    // MARK: - Persistence

    /// Drop all metadata and rebuild from tart list.
    /// Preserves nothing — use when metadata is corrupted or out of date.
    func resetMetadata() async {
        vms = []
        try? FileManager.default.removeItem(at: metadataURL)
        AppLogger.shared.log("VM metadata reset — rebuilding from tart list", source: "VMStore")
        await sync()
    }

    /// Reload metadata from disk (e.g. after a profile switch) then re-sync with tart.
    func reload() async {
        vms = []
        loadFromDisk()
        await sync()
    }

    func loadFromDisk() {
        let loaded: [VirtualMachine] = AppDatabase.shared.readOrDefault(.vms, default: [])
        vms = loaded
        AppLogger.shared.log("Loaded \(vms.count) VMs from disk", source: "VMStore")
        migrateLegacyBaseVMs()
    }

    /// One-time migration: fold legacy BaseVM records into the unified vms array.
    private func migrateLegacyBaseVMs() {
        struct LegacyBaseVM: Codable {
            let id: UUID
            var name: String
            var displayName: String?
            var osName: String?
            var defaultUsername: String?
            var cpuCount: Int?
            var memoryGB: Int?
            var diskGB: Int?
            var source: String?
            var status: String?
            var builtAt: Date?
            var registryImageRef: String?
            var installRosetta: Bool?
            var installHomebrew: Bool?
            var enableSSHDaemon: Bool?
        }
        let legacyList: [LegacyBaseVM]? = try? AppDatabase.shared.read(.baseVMs)
        guard let legacyList, !legacyList.isEmpty else { return }
        let knownNames = Set(vms.map(\.name))
        var added = 0
        for legacy in legacyList {
            guard !knownNames.contains(legacy.name) else { continue }
            var vm = VirtualMachine(name: legacy.name, isBaseVM: true)
            vm.displayName    = legacy.displayName ?? legacy.name
            vm.sshUsername    = legacy.defaultUsername ?? "baker"
            vm.cpuCount       = legacy.cpuCount ?? 4
            vm.memoryGB       = legacy.memoryGB ?? 8
            vm.diskGB         = legacy.diskGB ?? 80
            vm.vmSource       = legacy.source == "From registry" ? .registry : .local
            vm.buildStatus    = legacy.status == "ready" ? .ready :
                                legacy.status == "building" ? .building :
                                legacy.status == "error" ? .error : .notBuilt
            vm.builtAt        = legacy.builtAt
            vm.registryImageRef = legacy.registryImageRef
            vm.installRosetta  = legacy.installRosetta ?? true
            vm.installHomebrew = legacy.installHomebrew ?? true
            vm.enableSSHDaemon = legacy.enableSSHDaemon ?? true
            if let osStr = legacy.osName,
               let osName = MacOSRelease.Name(rawValue: osStr) {
                vm.osName = osName
                vm.macOSVersion = "macOS \(osStr)"
            }
            vms.append(vm)
            added += 1
        }
        if added > 0 {
            saveToDisk()
            AppLogger.shared.success(
                "Migrated \(added) Base VM(s) from legacy store", source: "VMStore")
        }
    }

    func saveToDisk() {
        AppDatabase.shared.writeSilently(vms, to: .vms)
    }
}
