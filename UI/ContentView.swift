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
        case .virtualMachines, .baseVMs, .mdmServers, .mdmEnrollment: return true
        case .installers, .registry, .activityLog, .recipes: return false
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

    /// Short label shown in the sidebar row.
    var sidebarLabel: String {
        switch self {
        case .virtualMachines: return "VMs"
        case .baseVMs:         return "Base VMs"
        case .recipes:         return "Recipes"
        case .installers:      return "Installers"
        case .registry:        return "Registry"
        case .mdmEnrollment:   return "Enrollment"
        case .mdmServers:      return "Servers"
        case .activityLog:     return "Activity"
        }
    }

    /// Full display name used for navigationTitle / window subtitle.
    var fullTitle: String { defaultLabel }

    // The four primary Library items, in keyboard-shortcut order (⌘1–⌘4)
    static var libraryItems: [SidebarItem] {
        [.virtualMachines, .baseVMs, .installers, .registry]
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
    @AppStorage("toast.disabled") private var toastsDisabled = false

    // View models lifted here so both the content column (list) and the
    // detail column (pane) share the same model instance.
    @State private var vmListModel        = VMListViewModel()
    @State private var baseVMModel        = BaseVMViewModel()
    @State private var mdmServersModel    = MDMServersViewModel()
    @State private var mdmEnrollmentModel = MDMEnrollmentViewModel()

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
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            } content: {
                ContentRouter(selection: selection.wrappedValue,
                              vmListModel: vmListModel,
                              baseVMModel: baseVMModel,
                              mdmServersModel: mdmServersModel,
                              mdmEnrollmentModel: mdmEnrollmentModel)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 930, max: 1000)
            } detail: {
                ZStack(alignment: .top) {
                    DetailColumn(selection: selection.wrappedValue,
                                 vmListModel: vmListModel,
                                 baseVMModel: baseVMModel,
                                 mdmServersModel: mdmServersModel,
                                 mdmEnrollmentModel: mdmEnrollmentModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !toastsDisabled {
                        ToastStackView()
                    }
                }
                .navigationSplitViewColumnWidth(min: 240, ideal: 320)
                .navigationTitle(appState.windowTitle)
                .navigationSubtitle(appState.windowSubtitle)
            }
            .navigationSplitViewStyle(.balanced)
            .onReceive(NotificationCenter.default.publisher(for: .navigateToLog)) { _ in
                storedSelection = SidebarItem.activityLog.rawValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuBarFocusVM)) { _ in
                storedSelection = SidebarItem.virtualMachines.rawValue
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
        } else {
            // ── 2-column layout: Sidebar | Full-width content ────────────────
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: selection)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            } detail: {
                ZStack(alignment: .top) {
                    ContentRouter(selection: selection.wrappedValue,
                                  vmListModel: vmListModel,
                                  baseVMModel: baseVMModel,
                                  mdmServersModel: mdmServersModel,
                                  mdmEnrollmentModel: mdmEnrollmentModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !toastsDisabled {
                        ToastStackView()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToLog)) { _ in
                storedSelection = SidebarItem.activityLog.rawValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuBarFocusVM)) { _ in
                storedSelection = SidebarItem.virtualMachines.rawValue
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
/// All .sheet and .confirmationDialog modifiers for MDM views live here so they
/// are anchored in the detail column where macOS can present them correctly.
private struct DetailColumn: View {
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var serverStore: MDMServerStore
    @EnvironmentObject var appState: AppState

    let selection: SidebarItem?
    @Bindable var vmListModel: VMListViewModel
    @Bindable var baseVMModel: BaseVMViewModel
    @Bindable var mdmServersModel: MDMServersViewModel
    @Bindable var mdmEnrollmentModel: MDMEnrollmentViewModel

    var body: some View {
        Group {
            switch selection {
            case .virtualMachines:
                vmDetail
            case .baseVMs:
                baseVMDetail
            case .mdmServers:
                mdmServersDetail
            case .mdmEnrollment:
                mdmEnrollmentDetail
            default:
                Color.clear
            }
        }
        // MARK: MDM Servers sheets (anchored in detail column)
        .sheet(isPresented: $mdmServersModel.isPresentingNewSheet) {
            MDMServerSheet(server: nil) { serverStore.add($0) }
        }
        .sheet(isPresented: Binding(
            get: { mdmServersModel.editingServer != nil },
            set: { if !$0 { mdmServersModel.editingServer = nil } }
        )) {
            if let toEdit = mdmServersModel.editingServer {
                MDMServerSheet(server: toEdit) { updated in
                    serverStore.update(id: toEdit.id) { s in
                        s.friendlyName   = updated.friendlyName
                        s.serverURL      = updated.serverURL
                        s.serverAuthType = updated.serverAuthType
                        s.serverUsername = updated.serverUsername
                        s.featureCheckEnrollment       = updated.featureCheckEnrollment
                        s.featureDeleteFromJamf        = updated.featureDeleteFromJamf
                        s.featureCheckInvitationStatus = updated.featureCheckInvitationStatus
                    }
                    mdmServersModel.editingServer = nil
                }
            }
        }
        .confirmationDialog(
            mdmServersModel.confirmDeleteServer.map { "Delete \"\($0.friendlyName)\"?" } ?? "Delete server?",
            isPresented: Binding(
                get: { mdmServersModel.confirmDeleteServer != nil },
                set: { if !$0 { mdmServersModel.confirmDeleteServer = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let server = mdmServersModel.confirmDeleteServer {
                Button("Delete Server", role: .destructive) {
                    serverStore.delete(id: server.id)
                    if mdmServersModel.selectedServerID == server.id {
                        mdmServersModel.selectedServerID = nil
                    }
                    mdmServersModel.confirmDeleteServer = nil
                }
                Button("Cancel", role: .cancel) { mdmServersModel.confirmDeleteServer = nil }
            }
        } message: {
            Text("This MDM server and its stored credentials will be permanently removed.")
        }
        // MARK: MDM Enrollment sheets (anchored in detail column)
        .sheet(isPresented: $mdmEnrollmentModel.isPresentingNewSheet) {
            MDMProfileSheet(servers: serverStore.servers) { profile in
                mdmEnrollmentModel.profiles.append(profile)
                mdmEnrollmentModel.save()
            }
        }
        .sheet(item: $mdmEnrollmentModel.editingProfile) { profile in
            MDMProfileSheet(servers: serverStore.servers, editing: profile) { updated in
                if let i = mdmEnrollmentModel.profiles.firstIndex(where: { $0.id == updated.id }) {
                    mdmEnrollmentModel.profiles[i] = updated
                    mdmEnrollmentModel.save()
                }
                mdmEnrollmentModel.editingProfile = nil
            }
        }
        .confirmationDialog(
            mdmEnrollmentModel.confirmDeleteProfile.map { "Delete \"\($0.displayName)\"?" } ?? "Delete profile?",
            isPresented: Binding(
                get: { mdmEnrollmentModel.confirmDeleteProfile != nil },
                set: { if !$0 { mdmEnrollmentModel.confirmDeleteProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = mdmEnrollmentModel.confirmDeleteProfile {
                Button("Delete Profile", role: .destructive) {
                    mdmEnrollmentModel.delete(profile)
                }
                Button("Cancel", role: .cancel) { mdmEnrollmentModel.confirmDeleteProfile = nil }
            }
        } message: {
            Text("This enrollment profile will be permanently removed.")
        }
    }

    // MARK: VM detail

    @ViewBuilder private var vmDetail: some View {
        if vmListModel.selectedIDs.count > 1 {
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
        if vmListModel.selectedIDs.count == 1,
           let id = vmListModel.selectedIDs.first {
            return vmStore.vms.first { $0.id == id }
        }
        return vmListModel.selectedVM
    }

    private var selectedVMs: [VirtualMachine] {
        vmStore.vms.filter { vmListModel.selectedIDs.contains($0.id) }
    }

    private var multiSelectionSummary: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(.largeTitle, weight: .light))
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

    // MARK: MDM Servers detail

    @ViewBuilder private var mdmServersDetail: some View {
        if let id = mdmServersModel.selectedServerID,
           serverStore.servers.contains(where: { $0.id == id }) {
            MDMServerDetailPane(
                serverID: id,
                onEdit:   { mdmServersModel.editingServer = serverStore.servers.first { $0.id == id } },
                onDelete: { mdmServersModel.confirmDeleteServer = serverStore.servers.first { $0.id == id } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Server Selected",
                systemImage: "server.rack",
                description: Text("Select an MDM server from the list.")
            )
        }
    }

    // MARK: MDM Enrollment detail

    @ViewBuilder private var mdmEnrollmentDetail: some View {
        if let id = mdmEnrollmentModel.selectedProfileID,
           mdmEnrollmentModel.profiles.contains(where: { $0.id == id }) {
            let resolvedServer = mdmEnrollmentModel.profiles
                .first(where: { $0.id == id })
                .flatMap { p in serverStore.servers.first { $0.id == p.serverID } }
            MDMProfileDetailPane(
                profile: mdmEnrollmentModel.profileBinding(for: id),
                server: resolvedServer,
                servers: serverStore.servers,
                onEdit:   { mdmEnrollmentModel.editingProfile = mdmEnrollmentModel.profiles.first { $0.id == id } },
                onDelete: { mdmEnrollmentModel.confirmDeleteProfile = mdmEnrollmentModel.profiles.first { $0.id == id } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Profile Selected",
                systemImage: "lock.shield",
                description: Text("Select an enrollment profile from the list.")
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
    @EnvironmentObject var pushManager: PushManager
    @EnvironmentObject var profileStore: ProfileStore
    @Binding var selection: SidebarItem?

    private var runningVMCount: Int {
        vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
    }

    private var activeDownloadCount: Int {
        appState.activeIPSWDownloads.count + appState.registryDownloads.count
    }

    private var activePushCount: Int {
        pushManager.active.count
    }
    
    var body: some View {
//        Spacer()
        List(selection: $selection) {

            // MARK: Library
            Section("Library") {
                libraryRow(.virtualMachines, shortcut: "1",
                           badge: runningVMCount > 0 ? "\(runningVMCount)" : nil)
                libraryRow(.baseVMs,         shortcut: "2")
                libraryRow(.installers,      shortcut: "3",
                           badge: activeDownloadCount > 0 ? "\(activeDownloadCount)" : nil)
                libraryRow(.registry,        shortcut: "4")
            }

            // MARK: Build
            Section("Build") {
                libraryRow(.recipes, shortcut: "5")
            }

            // MARK: MDM (feature-flagged)
            if theme.mdmEnabled {
                Section("MDM") {
                    sidebarItem(.mdmEnrollment)
                    sidebarItem(.mdmServers)
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

            // MARK: System
            Section("System") {
                sidebarItem(.activityLog,
                            badge: activePushCount > 0 ? "\(activePushCount)" : nil)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { OvenStatusBar() }
        .safeAreaInset(edge: .top, spacing: 0) {
            if profileStore.profiles.count > 1 {
                profileSwitcherHeader
            }
        }
        // Clear sidebar filters when navigating away from VMs.
        .onChange(of: selection) { _, newValue in
            if newValue != .virtualMachines {
                appState.sidebarTagFilter = nil
                appState.sidebarStatusFilter = nil
            }
        }
    }

    // MARK: - Profile switcher header

    private var profileSwitcherHeader: some View {
        Menu {
            ForEach(profileStore.profiles) { profile in
                Button {
                    profileStore.switchToProfile(id: profile.id)
                } label: {
                    if profile.id == profileStore.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
                .disabled(profile.id == profileStore.activeProfileID)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(profileStore.activeProfile.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .help("Switch profile")
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
        item.sidebarLabel
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
                    .font(.callout.weight(.light))
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
    @Bindable var mdmServersModel: MDMServersViewModel
    @Bindable var mdmEnrollmentModel: MDMEnrollmentViewModel

    var body: some View {
        switch selection {
        case .virtualMachines: VMListView(model: vmListModel)
        case .baseVMs:         BaseVMView(model: baseVMModel)
        case .recipes:         RecipesView()
        case .installers:      InstallerView()
        case .registry:        RegistryView()
        case .mdmEnrollment:   MDMEnrollmentView(model: mdmEnrollmentModel)
        case .mdmServers:      MDMServersView(model: mdmServersModel)
        case .activityLog:     LogView()
        case .none:
            ContentUnavailableView("Select an item", systemImage: "sidebar.left",
                                   description: Text("Choose a section from the sidebar."))
        }
    }
}
