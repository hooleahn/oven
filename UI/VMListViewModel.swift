import SwiftUI

enum VMSortOrder: String, CaseIterable {
    case name        = "Name"
    case osVersion   = "OS Version"
    case createdAt   = "Created"
    case lastStarted = "Last Started"
}

// MARK: - VM Tab

enum VMTab: String, CaseIterable {
    case all = "All"
    case running = "Running"
    case stopped = "Stopped"
}

// MARK: - List Density

enum ListDensity: String, CaseIterable {
    case cozy    = "Cozy"
    case compact = "Compact"
    case tight   = "Tight"

    /// Vertical padding (top + bottom) applied to each VMCard row in list mode.
    var verticalPadding: CGFloat {
        switch self {
        case .cozy:    return 14
        case .compact: return 10
        case .tight:   return 6
        }
    }

    var systemImage: String {
        switch self {
        case .cozy:    return "rectangle.grid.1x2"
        case .compact: return "list.bullet"
        case .tight:   return "list.dash"
        }
    }
}

// MARK: - VMListViewModel

@MainActor
@Observable
final class VMListViewModel {

    // MARK: - Filter / sort state
    var selectedTab: VMTab = .all
    var selectedTagFilters: Set<String> = []
    var selectedOSFilters:  Set<String> = []
    var selectedMDMServerFilters: Set<UUID> = []
    var sortOrder: VMSortOrder = .name
    var isListView = false
    var density: ListDensity = .cozy

    // MARK: - Selection / action state
    /// Multi-selection set used by the native List in list mode.
    var selectedIDs: Set<VirtualMachine.ID> = []
    var selectedVM: VirtualMachine?          // kept for grid mode / single-tap
    var confirmDelete: VirtualMachine?
    var confirmStop:   VirtualMachine?
    var cloneVM:       VirtualMachine?
    var pendingLaunchVM: VirtualMachine?
    var editingVM: VirtualMachine?
    var pushVM: VirtualMachine?          // VM to push to registry from context menu
    var executeCommandVM: VirtualMachine?   // VM targeted by execute command sheet
    var executeCommandMethod: ExecMethod = .ssh
    var macOSLimitError: String?    // shown when 2 VMs already running
    var confirmStopAll = false      // Stop All confirmation
    var confirmBulkDelete = false   // bulk delete confirmation
    /// Set when Jamf deletion fails on a single-VM delete; drives the "remove from tart anyway?" alert.
    var jamfDeleteFailed: (vm: VirtualMachine, message: String)? = nil
    var bulkAddTagSheet = false
    var bulkRemoveTagSheet = false

    // MARK: - Derived lists (read from stores injected at call site)

    func filteredVMs(from vms: [VirtualMachine],
                     searchQuery: String,
                     sidebarTagFilter: String? = nil,
                     sidebarStatusFilter: VMTab? = nil) -> [VirtualMachine] {
        // Working VMs only — base VMs are shown in the Base VMs view
        let workingVMs = vms.filter { !$0.effectivelyBase }
        var base: [VirtualMachine]

        // Sidebar status filter takes precedence over the toolbar tab filter.
        let effectiveTab = sidebarStatusFilter ?? selectedTab
        switch effectiveTab {
        case .all:     base = workingVMs
        case .running: base = workingVMs.filter { $0.status == .running || $0.status == .suspended }
        case .stopped: base = workingVMs.filter { $0.status == .stopped }
        }

        // Sidebar tag filter takes precedence over toolbar tag filters.
        if let sidebarTag = sidebarTagFilter {
            base = base.filter { $0.tags.contains(sidebarTag) }
        } else if !selectedTagFilters.isEmpty {
            base = base.filter { selectedTagFilters.isSubset(of: Set($0.tags)) }
        }
        if !selectedOSFilters.isEmpty {
            base = base.filter { vm in
                selectedOSFilters.contains(vm.osVersion)
            }
        }
        if !selectedMDMServerFilters.isEmpty {
            base = base.filter { vm in
                vm.mdmServerID.map { selectedMDMServerFilters.contains($0) } ?? false
            }
        }
        if !searchQuery.isEmpty {
            base = base.filter {
                $0.name.localizedStandardContains(searchQuery) ||
                $0.displayName.localizedStandardContains(searchQuery) ||
                $0.description.localizedStandardContains(searchQuery) ||
                $0.tags.contains(where: { $0.localizedStandardContains(searchQuery) })
            }
        }

        switch sortOrder {
        case .name:        return base.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .osVersion:   return base.sorted { $0.osVersion < $1.osVersion }
        case .createdAt:     return base.sorted { $0.createdAt > $1.createdAt }
        case .lastStarted: return base.sorted { ($0.lastStartedAt ?? .distantPast) > ($1.lastStartedAt ?? .distantPast) }
        }
    }

    func allTags(from vms: [VirtualMachine]) -> [String] {
        Array(Set(vms.flatMap { $0.tags })).sorted()
    }

    func allMDMServers(from vms: [VirtualMachine], servers: [MDMServer]) -> [MDMServer] {
        let usedIDs = Set(vms.compactMap { $0.mdmServerID })
        return servers.filter { usedIDs.contains($0.id) }
            .sorted { $0.friendlyName < $1.friendlyName }
    }

    func allOSMajors(from vms: [VirtualMachine]) -> [String] {
        let names = ["Golden Gate", "Tahoe", "Sequoia", "Sonoma", "Ventura", "Monterey"]
        return names.filter { major in vms.contains { $0.osName.rawValue == major } }
    }

    func osVersions(under major: String, from vms: [VirtualMachine]) -> [String] {
        Array(Set(vms
            .filter { $0.osName.rawValue == major && !$0.osVersion.isEmpty }
            .map { $0.osVersion }
        )).sorted()
    }

    // MARK: - Actions

    func startVM(_ vm: VirtualMachine,
                 mode: TartService.RunMode = .native,
                 vmStore: VMStore,
                 appState: AppState) async {
        let label = vm.displayName.isEmpty ? vm.name : vm.displayName
        let opID = appState.beginOperation(vmName: label, kind: .start)
        let stream = await vmStore.start(vm: vm, mode: mode)
        let result = await StreamConsumer.consume(stream, onStdout: { line in
            appState.appendLog(operationID: opID, line: line)
        })
        appState.finishOperation(id: opID)

        if result.exitCode != 0 {
            let errLine = result.stderrLines
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                ?? "tart exited with code \(result.exitCode)"
            AppLogger.shared.error("Failed to start \"\(label)\": \(errLine)", source: "VMStore")
        } else {
            await NotificationService.shared.notifyVMStopped(vmName: label)
        }

        await vmStore.sync()
    }
}
