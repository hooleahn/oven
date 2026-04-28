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
    var pushVM: VirtualMachine?     // VM to push to registry from context menu
    var macOSLimitError: String?    // shown when 2 VMs already running
    var confirmStopAll = false      // Stop All confirmation
    var confirmBulkDelete = false   // bulk delete confirmation
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
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            base = base.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.displayName.localizedCaseInsensitiveContains(q) ||
                $0.description.localizedCaseInsensitiveContains(q) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }
        }

        switch sortOrder {
        case .name:        return base.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        case .osVersion:   return base.sorted { $0.osVersion < $1.osVersion }
        case .createdAt:     return base.sorted { $0.createdAt > $1.createdAt }
        case .lastStarted: return base.sorted { ($0.lastStartedAt ?? .distantPast) > ($1.lastStartedAt ?? .distantPast) }
        }
    }

    func allTags(from vms: [VirtualMachine]) -> [String] {
        Array(Set(vms.flatMap { $0.tags })).sorted()
    }

    func allOSMajors(from vms: [VirtualMachine]) -> [String] {
        let names = ["Tahoe", "Sequoia", "Sonoma", "Ventura", "Monterey"]
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
        let opID = appState.beginOperation(vmName: vm.displayName, kind: .start)
        let stream = await vmStore.start(vm: vm, mode: mode)
        await StreamConsumer.consume(stream, onStdout: { line in
            appState.appendLog(operationID: opID, line: line)
        })
        appState.finishOperation(id: opID)
        await vmStore.sync()
    }
}
