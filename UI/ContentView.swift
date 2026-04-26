import SwiftUI

// MARK: - Sidebar destination

enum SidebarItem: String, Hashable, CaseIterable {
    case virtualMachines
    case baseVMs
    case recipes
    case installers
    case registry
    case mdmEnrollment
    case mdmServers
    case activityLog

    // Static fallbacks used when AppTheme is not available (e.g. enum context)
    var defaultIcon: String {
        switch self {
        case .virtualMachines: return "desktopcomputer"
        case .baseVMs:         return "shippingbox"
        case .recipes:         return "doc.text"
        case .installers:      return "arrow.down.circle"
        case .registry:        return "externaldrive.connected.to.line.below"
        case .mdmEnrollment:   return "lock.shield"
        case .mdmServers:      return "server.rack"
        case .activityLog:     return "list.bullet.rectangle"
        }
    }

    /// Whether this destination has a meaningful third (detail) column.
    /// 2-column destinations stretch their content to full width instead.
    var hasDetailPane: Bool {
        switch self {
        case .virtualMachines, .baseVMs, .mdmServers: return true
        case .installers, .registry, .mdmEnrollment, .activityLog, .recipes: return false
        }
    }

    var defaultLabel: String {
        switch self {
        case .virtualMachines: return "Virtual Machines"
        case .baseVMs:         return "Base VMs"
        case .recipes:         return "Packer Templates"
        case .installers:      return "macOS Installers"
        case .registry:        return "Image Registry"
        case .mdmEnrollment:   return "MDM Enrollment"
        case .mdmServers:      return "MDM Servers"
        case .activityLog:     return "Activity Log"
        }
    }

    // The five primary Library items, in keyboard-shortcut order (⌘1–⌘5)
    static var libraryItems: [SidebarItem] {
        [.virtualMachines, .baseVMs, .recipes, .installers, .registry]
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var serverStore: MDMServerStore
    @EnvironmentObject var templateStore: PackerTemplateStore
    @EnvironmentObject var blockStore: BuildingBlockStore

    // SceneStorage persists the selected tab across relaunches within the same scene.
    @SceneStorage("oven.selectedTab") private var storedSelection: String = SidebarItem.virtualMachines.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // View models lifted here so both the content column (list) and the
    // detail column (pane) share the same model instance.
    @State private var vmListModel    = VMListViewModel()
    @State private var baseVMModel    = BaseVMViewModel()

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: storedSelection) },
            set: { storedSelection = $0?.rawValue ?? SidebarItem.virtualMachines.rawValue }
        )
    }

    var body: some View {
        let currentItem = SidebarItem(rawValue: storedSelection)

        if currentItem?.hasDetailPane == true {
            // ── 3-column layout: Sidebar | Content list | Detail pane ────────
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: selection)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } content: {
                ContentRouter(selection: selection.wrappedValue,
                              vmListModel: vmListModel,
                              baseVMModel: baseVMModel)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 500, max: 800)
            } detail: {
                DetailColumn(selection: selection.wrappedValue,
                             vmListModel: vmListModel,
                             baseVMModel: baseVMModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(appState.windowTitle)
                    .navigationSubtitle(appState.windowSubtitle)
            }
            .navigationSplitViewStyle(.balanced)
            .onChange(of: storedSelection) { _, raw in
                appState.selectedVMID     = nil
                appState.selectedBaseVMID = nil
                guard let item = SidebarItem(rawValue: raw) else { return }
                switch item {
                case .installers:    appState.windowTitle = "macOS Installers"; appState.windowSubtitle = ""
                case .mdmEnrollment: appState.windowTitle = "MDM Enrollment";   appState.windowSubtitle = ""
                case .mdmServers:    appState.windowTitle = "MDM Servers";      appState.windowSubtitle = ""
                default: break
                }
            }
        } else {
            // ── 2-column layout: Sidebar | Full-width content ────────────────
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: selection)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } detail: {
                ContentRouter(selection: selection.wrappedValue,
                              vmListModel: vmListModel,
                              baseVMModel: baseVMModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: storedSelection) { _, raw in
                appState.selectedVMID     = nil
                appState.selectedBaseVMID = nil
                guard let item = SidebarItem(rawValue: raw) else { return }
                switch item {
                case .installers:    appState.windowTitle = "macOS Installers"; appState.windowSubtitle = ""
                case .mdmEnrollment: appState.windowTitle = "MDM Enrollment";   appState.windowSubtitle = ""
                case .mdmServers:    appState.windowTitle = "MDM Servers";      appState.windowSubtitle = ""
                default: break
                }
            }
        }
    }

}

// MARK: - Detail column

/// Renders the correct detail pane for the currently selected tab and item.
/// Lives in the third column of the NavigationSplitView.
private struct DetailColumn: View {
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var serverStore: MDMServerStore
    @EnvironmentObject var appState: AppState

    let selection: SidebarItem?
    @Bindable var vmListModel: VMListViewModel
    @Bindable var baseVMModel: BaseVMViewModel

    var body: some View {
        switch selection {
        case .virtualMachines:
            vmDetail

        case .baseVMs:
            baseVMDetail

        default:
            // Tabs that handle their own layout (no detail pane)
            Color.clear
        }
    }

    // MARK: VM detail

    @ViewBuilder private var vmDetail: some View {
        if vmListModel.selectedIDs.count > 1 {
            // Multi-selection summary
            multiSelectionSummary
        } else if let vm = selectedVM {
            VMDetailPane(
                vm: vm,
                onDismiss: {
                    vmListModel.selectedIDs.removeAll()
                    vmListModel.selectedVM = nil
                    appState.selectedVMID  = nil
                },
                onStart: { Task { await startVM(vm) } }
            )
            .environmentObject(baseVMStore)
            .environmentObject(serverStore)
        } else {
            ContentUnavailableView(
                "No VM Selected",
                systemImage: "desktopcomputer",
                description: Text("Select a virtual machine from the list.")
            )
        }
    }

    private var selectedVM: VirtualMachine? {
        // List mode: single-item selectedIDs set
        if vmListModel.selectedIDs.count == 1,
           let id = vmListModel.selectedIDs.first {
            return vmStore.vms.first { $0.id == id }
        }
        // Grid mode: selectedVM property
        return vmListModel.selectedVM
    }

    private var selectedVMs: [VirtualMachine] {
        vmStore.vms.filter { vmListModel.selectedIDs.contains($0.id) }
    }

    private var multiSelectionSummary: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(vmListModel.selectedIDs.count) VMs Selected")
                .font(.headline)
            Text(selectedVMs
                    .map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                    .joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Divider()
            BulkActionsMenu(
                count: vmListModel.selectedIDs.count,
                selectedVMs: selectedVMs,
                vmStore: vmStore,
                model: vmListModel
            )
            Button("Clear Selection") {
                vmListModel.selectedIDs.removeAll()
                appState.selectedVMID = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func startVM(_ vm: VirtualMachine, mode: TartService.RunMode = .native) async {
        guard !vm.effectivelyBase else { return }
        let runningCount = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
        if runningCount >= 2 {
            let names = vmStore.vms
                .filter { $0.status == .running || $0.status == .suspended }
                .map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                .joined(separator: ", ")
            vmListModel.macOSLimitError = "macOS allows at most 2 simultaneous VMs. Currently running: \(names)."
            return
        }
        await vmListModel.startVM(vm, mode: mode, vmStore: vmStore, appState: appState)
    }

    // MARK: Base VM detail

    @ViewBuilder private var baseVMDetail: some View {
        if let selected = baseVMModel.selectedBaseVM(from: baseVMStore.baseVMs) {
            BaseVMDetailPane(
                baseVM: selected,
                onBuild:    { Task { await baseVMStore.build(baseVM: selected) } },
                onDelete:   { baseVMModel.confirmDelete = selected },
                onCreateVM: { baseVMModel.createVMFromBase = selected }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Base VM Selected",
                systemImage: "shippingbox",
                description: Text("Select a base VM from the list.")
            )
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tagStore: TagStore
    @Binding var selection: SidebarItem?

    private var runningVMCount: Int {
        vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
    }

    private var activeDownloadCount: Int {
        appState.activeIPSWDownloads.count + appState.registryDownloads.count
    }

    var body: some View {
        List(selection: $selection) {

            // MARK: Library
            Section {
                libraryRow(.virtualMachines, shortcut: "1",
                           badge: runningVMCount > 0 ? "\(runningVMCount)" : nil)
                libraryRow(.baseVMs,         shortcut: "2")
                libraryRow(.recipes,         shortcut: "3")
                libraryRow(.installers,      shortcut: "4",
                           badge: activeDownloadCount > 0 ? "\(activeDownloadCount)" : nil)
                libraryRow(.registry,        shortcut: "5")
            } header: {
                SidebarSectionHeader("Library")
            }

            // MARK: MDM (feature-flagged)
            if theme.mdmEnabled {
                Section {
                    sidebarItem(.mdmServers)
                    sidebarItem(.mdmEnrollment)
                } header: {
                    SidebarSectionHeader("MDM")
                }
            }

            // MARK: Tags
            // Only shown when at least one tag has a colour assigned.
            // Tapping a tag row sets appState.sidebarTagFilter; VMListView
            // reads this to narrow its filteredVMs result.
            let managedTags = tagStore.managedTags   // already sorted
            if !managedTags.isEmpty {
                Section {
                    ForEach(managedTags, id: \.self) { tag in
                        Button {
                            // Toggle: tapping the active tag clears the filter.
                            if appState.sidebarTagFilter == tag {
                                appState.sidebarTagFilter = nil
                            } else {
                                appState.sidebarTagFilter = tag
                                // Navigate to VMs when a tag is picked.
                                selection = .virtualMachines
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(tagStore.color(for: tag))
                                    .frame(width: 8, height: 8)
                                Text(tag)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if appState.sidebarTagFilter == tag {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    SidebarSectionHeader("Tags")
                }
            }

            // MARK: Filters
            // Quick status filters for the VM list.
            // Tapping sets appState.sidebarStatusFilter; VMListView reads it.
            Section {
                filterRow("Running", icon: "circle.fill",  color: .green,  filter: .running)
                filterRow("Stopped", icon: "circle",       color: .secondary, filter: .stopped)
            } header: {
                SidebarSectionHeader("Filters")
            }

            // MARK: General
            Section {
                sidebarItem(.activityLog)
            } header: {
                SidebarSectionHeader("General")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { OvenStatusBar() }
        // Clear sidebar filters when navigating away from VMs.
        .onChange(of: selection) { _, newValue in
            if newValue != .virtualMachines {
                appState.sidebarTagFilter = nil
                appState.sidebarStatusFilter = nil
            }
        }
    }

    // MARK: - Row builders

    /// Library row with ⌘N keyboard shortcut.
    @ViewBuilder
    private func libraryRow(_ item: SidebarItem, shortcut: String, badge: String? = nil) -> some View {
        Label(themedLabel(item), systemImage: themedIcon(item))
            .badge(badge)
            .tag(item)
            .keyboardShortcut(KeyEquivalent(Character(shortcut)), modifiers: .command)
    }

    /// Standard sidebar row without a keyboard shortcut.
    @ViewBuilder
    private func sidebarItem(_ item: SidebarItem, badge: String? = nil) -> some View {
        Label(themedLabel(item), systemImage: themedIcon(item))
            .badge(badge)
            .tag(item)
    }

    /// Status-filter row. Tapping toggles the filter and navigates to VMs.
    @ViewBuilder
    private func filterRow(_ label: String, icon: String, color: Color, filter: VMTab) -> some View {
        let isActive = appState.sidebarStatusFilter == filter
        Button {
            if isActive {
                appState.sidebarStatusFilter = nil
            } else {
                appState.sidebarStatusFilter = filter
                selection = .virtualMachines
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Theme helpers

    private func themedLabel(_ item: SidebarItem) -> String {
        switch item {
        case .virtualMachines: return theme.virtualMachines
        case .baseVMs:         return theme.baseVMs
        case .recipes:         return theme.recipes
        case .installers:      return theme.installers
        case .registry:        return theme.registry
        case .mdmEnrollment:   return theme.mdmEnrollment
        case .mdmServers:      return theme.mdmServers
        case .activityLog:     return theme.logs
        }
    }

    private func themedIcon(_ item: SidebarItem) -> String {
        switch item {
        case .virtualMachines: return theme.vmIcon
        case .baseVMs:         return theme.baseVMIcon
        case .recipes:         return "doc.text"
        case .installers:      return theme.installerIcon
        case .registry:        return theme.registryIcon
        case .mdmEnrollment:   return "lock.shield"
        case .mdmServers:      return "server.rack"
        case .activityLog:     return "list.bullet.rectangle"
        }
    }
}

// MARK: - Sidebar section header

private struct SidebarSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

// MARK: - Status bar

struct OvenStatusBar: View {
    @EnvironmentObject var depManager: DependencyManager
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusLabel)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            // Preferences button — opens the ⌘, Settings window
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Preferences (⌘,)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
    }

    private var statusColor: Color {
        if !depManager.allReady { return .orange }
        if depManager.hasUpdatesAvailable { return .orange }
        return .green
    }

    private var statusLabel: String {
        if !depManager.allReady { return "Setting up…" }
        let updates = depManager.dependencies.filter { $0.status == .updateAvailable }
        if !updates.isEmpty {
            let names = updates.map(\.displayName).joined(separator: ", ")
            return "Updates available: \(names)"
        }
        return "All tools ready"
    }
}

// MARK: - Content router

/// Routes the selected SidebarItem to the appropriate list/content view.
/// Displayed in the content column of the NavigationSplitView.
struct ContentRouter: View {
    @EnvironmentObject var theme: AppTheme
    let selection: SidebarItem?
    @Bindable var vmListModel: VMListViewModel
    @Bindable var baseVMModel: BaseVMViewModel

    var body: some View {
        switch selection {
        case .virtualMachines: VMListView(model: vmListModel)
        case .baseVMs:         BaseVMView(model: baseVMModel)
        case .recipes:         RecipesView()
        case .installers:      InstallerView()
        case .registry:        RegistryView()
        case .mdmEnrollment:   MDMEnrollmentView()
        case .mdmServers:      MDMServersView()
        case .activityLog:     LogView()
        case .none:
            ContentUnavailableView("Select an item", systemImage: "sidebar.left",
                                   description: Text("Choose a section from the sidebar."))
        }
    }
}
