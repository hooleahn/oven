import SwiftUI
import AppKit

// MARK: - VMListView

struct VMListView: View {
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serverStore: MDMServerStore
    @EnvironmentObject var tagStore: TagStore
    /// Model is owned by ContentView so the detail column can also access it.
    @Bindable var model: VMListViewModel

    @AppStorage("oven.vmList.density") private var density: ListDensity = .cozy



    /// All tags across all VMs for filter picker and autocomplete
    var filteredVMs: [VirtualMachine] {
        model.filteredVMs(from: vmStore.vms,
                          searchQuery: appState.searchQuery,
                          sidebarTagFilter: appState.sidebarTagFilter,
                          sidebarStatusFilter: appState.sidebarStatusFilter)
    }
    private var workingVMs: [VirtualMachine] { vmStore.vms.filter { !$0.effectivelyBase } }
    var allTags: [String]       { model.allTags(from: workingVMs) }
    var allOSMajors: [String]   { model.allOSMajors(from: workingVMs) }
    var allMDMServers: [MDMServer] { model.allMDMServers(from: workingVMs, servers: serverStore.servers) }
    func osVersions(under major: String) -> [String] { model.osVersions(under: major, from: workingVMs) }

    /// VMs corresponding to the current multi-selection
    private var selectedVMs: [VirtualMachine] {
        vmStore.vms.filter { model.selectedIDs.contains($0.id) }
    }

    /// Animated rotation for the refresh button
    @State private var refreshRotation: Double = 0
    @State private var isRefreshing: Bool = false

    var body: some View {
        // ── Content column: list only ──────────────────────────────────────
        // The detail pane lives in ContentView's detail column, not here.
        contentStack
            .navigationTitle("Virtual Machines")
            .task { updateWindowTitle() }
            .onChange(of: model.selectedIDs, initial: false) { _, newIDs in
                appState.selectedVMID = newIDs.count == 1 ? newIDs.first : nil
                if newIDs.isEmpty { model.selectedVM = nil }
                updateWindowTitle()
            }
            .onChange(of: model.selectedVM, initial: false) { _, vm in
                appState.selectedVMID = vm?.id
                updateWindowTitle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuBarFocusVM)) { note in
                guard let id = note.userInfo?["vmID"] as? VirtualMachine.ID else { return }
                model.selectedIDs = [id]
            }
            .modifier(VMListSheets(
                model: model,
                vmStore: vmStore,
                baseVMStore: baseVMStore,
                appState: appState,
                serverStore: serverStore
            ))
            .searchable(text: $appState.searchQuery, prompt: "Search VMs…")
            .safeAreaInset(edge: .bottom, spacing: 0) { floatingActionBar }
            .toolbar { toolbarContent }
            .task { await vmStore.sync() }
            .refreshable { await vmStore.sync() }
            .onChange(of: vmStore.vms) { _, vms in
                Task { @MainActor in
                    if let id = self.model.selectedVM?.id {
                        self.model.selectedVM = vms.first { $0.id == id }
                    }
                    let validIDs = Set(vms.map { $0.id })
                    self.model.selectedIDs = self.model.selectedIDs.intersection(validIDs)
                }
            }
    }

    private var contentStack: some View {
        VStack(spacing: 0) {
            activeTagFilterBar
            if vmStore.vms.isEmpty && !vmStore.isSyncing {
                emptyState
            } else if model.isListView {
                vmList
            } else {
                vmGrid
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.isPresentingNewVM = true
            } label: {
                Label("New VM", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New VM (⌘N)")
        }
        ToolbarItem(placement: .automatic) {
            filterSortMenu
        }
        ToolbarItem(placement: .automatic) {
            Button { model.isListView.toggle() } label: {
                Image(systemName: model.isListView ? "square.grid.2x2" : "list.bullet")
            }
            .help(model.isListView ? "Switch to grid view" : "Switch to list view")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    refreshRotation = 360
                }
                Task {
                    await vmStore.sync()
                    isRefreshing = false
                    refreshRotation = 0
                }
            } label: {
                Label("Refresh VMs", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh VM list (⌘R)")
        }
    }

    // MARK: Filter & Sort consolidated menu

    /// True when any filter deviates from the defaults.
    private var isAnyFilterActive: Bool {
        model.selectedTab != .all ||
        !model.selectedTagFilters.isEmpty ||
        !model.selectedOSFilters.isEmpty ||
        !model.selectedMDMServerFilters.isEmpty
    }

    private var activeFilterCount: Int {
        (model.selectedTab != .all ? 1 : 0) +
        model.selectedTagFilters.count +
        model.selectedOSFilters.count +
        model.selectedMDMServerFilters.count
    }

    @ViewBuilder private var filterSortMenu: some View {
        Menu {
            // ── Show (tab filter) ──────────────────────────────────────────
            Section("Show") {
                ForEach(VMTab.allCases, id: \.self) { tab in
                    Button {
                        model.selectedTab = tab
                    } label: {
                        HStack {
                            Text(tab.rawValue)
                            if model.selectedTab == tab { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            // ── Tags ──────────────────────────────────────────────────────
            if !allTags.isEmpty {
                Section("Tags") {
                    if !model.selectedTagFilters.isEmpty {
                        Button("Clear Tag Filters") { model.selectedTagFilters.removeAll() }
                    }
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            if model.selectedTagFilters.contains(tag) { model.selectedTagFilters.remove(tag) }
                            else { model.selectedTagFilters.insert(tag) }
                        } label: {
                            HStack {
                                Circle().fill(tagStore.color(for: tag)).frame(width: 8, height: 8)
                                Text(tag)
                                if model.selectedTagFilters.contains(tag) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }

            // ── macOS ─────────────────────────────────────────────────────
            if !allOSMajors.isEmpty {
                Section("macOS") {
                    if !model.selectedOSFilters.isEmpty {
                        Button("Clear OS Filters") { model.selectedOSFilters.removeAll() }
                    }
                    ForEach(allOSMajors, id: \.self) { major in
                        let versions = osVersions(under: major)
                        if versions.count > 1 {
                            Button {
                                let all = versions.allSatisfy { model.selectedOSFilters.contains($0) }
                                if all { versions.forEach { model.selectedOSFilters.remove($0) } }
                                else   { versions.forEach { model.selectedOSFilters.insert($0) } }
                            } label: {
                                HStack {
                                    Text(major).fontWeight(.medium)
                                    if versions.allSatisfy({ model.selectedOSFilters.contains($0) }) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            ForEach(versions, id: \.self) { ver in
                                Button {
                                    if model.selectedOSFilters.contains(ver) { model.selectedOSFilters.remove(ver) }
                                    else { model.selectedOSFilters.insert(ver) }
                                } label: {
                                    HStack {
                                        Text("  " + ver)
                                        if model.selectedOSFilters.contains(ver) { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } else if let ver = versions.first {
                            Button {
                                if model.selectedOSFilters.contains(ver) { model.selectedOSFilters.remove(ver) }
                                else { model.selectedOSFilters.insert(ver) }
                            } label: {
                                HStack {
                                    Text(major)
                                    if model.selectedOSFilters.contains(ver) { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
            }

            // ── MDM Server ────────────────────────────────────────────────
            if !allMDMServers.isEmpty {
                Section("MDM Server") {
                    if !model.selectedMDMServerFilters.isEmpty {
                        Button("Clear MDM Filters") { model.selectedMDMServerFilters.removeAll() }
                    }
                    ForEach(allMDMServers) { server in
                        Button {
                            if model.selectedMDMServerFilters.contains(server.id) {
                                model.selectedMDMServerFilters.remove(server.id)
                            } else {
                                model.selectedMDMServerFilters.insert(server.id)
                            }
                        } label: {
                            HStack {
                                Text(server.friendlyName)
                                if model.selectedMDMServerFilters.contains(server.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            // ── Sort by ───────────────────────────────────────────────────
            Section("Sort By") {
                ForEach(VMSortOrder.allCases, id: \.self) { order in
                    Button {
                        model.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if model.sortOrder == order { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            // ── Density (list view only) ───────────────────────────────────
            if model.isListView {
                Section("Density") {
                    ForEach(ListDensity.allCases, id: \.self) { d in
                        Button {
                            density = d
                            model.density = d
                        } label: {
                            HStack {
                                Image(systemName: d.systemImage)
                                Text(d.rawValue)
                                if density == d { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease")
                if isAnyFilterActive {
                    badgeView(activeFilterCount)
                }
            }
        }
        .help(isAnyFilterActive ? "\(activeFilterCount) filter(s) active" : "Filter & Sort")
    }

    // MARK: Floating action bar

    @ViewBuilder private var floatingActionBar: some View {
        let runningVMs = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }
        let showBulk = model.isListView && model.selectedIDs.count >= 2
        let showStopAll = !runningVMs.isEmpty

        if showBulk || showStopAll {
            HStack(spacing: 10) {
                if showBulk {
                    // Start selected
                    Button {
                        let runningCount = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
                        let toStart = selectedVMs.filter { $0.status == .stopped }.prefix(max(0, 2 - runningCount))
                        guard !toStart.isEmpty else {
                            let names = vmStore.vms
                                .filter { $0.status == .running || $0.status == .suspended }
                                .map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                                .joined(separator: ", ")
                            model.macOSLimitError = "macOS allows at most 2 simultaneous VMs. Currently running: \(names)."
                            return
                        }
                        Task {
                            await withTaskGroup(of: Void.self) { group in
                                for vm in toStart {
                                    group.addTask {
                                        let stream = await vmStore.start(vm: vm, mode: .native)
                                        for await _ in stream {}
                                    }
                                }
                            }
                            await vmStore.sync()
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Stop selected
                    Button {
                        for vm in selectedVMs where vm.status == .running || vm.status == .suspended {
                            Task { try? await vmStore.stop(vm: vm) }
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Divider().frame(height: 18)

                    // Bulk delete
                    Button(role: .destructive) {
                        model.confirmBulkDelete = true
                    } label: {
                        Label(model.selectedIDs.count == 1 ? "Delete" : "Delete \(model.selectedIDs.count)",
                              systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.delete, modifiers: .command)

                    Spacer()

                    Text("\(model.selectedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Clear") { model.selectedIDs.removeAll() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showBulk && showStopAll {
                    Divider().frame(height: 18)
                }

                if showStopAll {
                    if !showBulk { Spacer() }
                    Button {
                        model.confirmStopAll = true
                    } label: {
                        Label("Stop All (\(runningVMs.count))", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: showBulk)
            .animation(.easeInOut(duration: 0.2), value: showStopAll)
        }
    }

    // MARK: Active tag filter bar

    @ViewBuilder private var activeTagFilterBar: some View {
        if !model.selectedTagFilters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.selectedTagFilters.sorted(), id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.caption.weight(.medium))
                            Button {
                                model.selectedTagFilters.remove(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                    }
                    Button("Clear") {
                        model.selectedTagFilters.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)
            Divider()
        }
    }

    private func badgeView(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
    }

    // MARK: Grid

    private var vmGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 230), spacing: 12)],
                spacing: 12
            ) {
                ForEach(filteredVMs) { vm in
                    VMCard(
                        vm: vm,
                        isSelected: model.selectedVM?.id == vm.id,
                        onSelect: {
                            if model.selectedVM?.id == vm.id {
                                model.selectedVM = nil
                                model.selectedIDs = []
                            } else {
                                model.selectedVM = vm
                                model.selectedIDs = [vm.id]
                            }
                        },
                        onStart: { model.pendingLaunchVM = vm },
                        onStop:  { model.confirmStop = vm },
                        onEdit:  { model.editingVM = vm },
                        onClone: { model.cloneVM = vm },
                        onDelete: { model.confirmDelete = vm },
                        onExecSSH: {
                            model.executeCommandVM = vm
                            model.executeCommandMethod = .ssh
                        },
                        onExecGuestAgent: {
                            model.executeCommandVM = vm
                            model.executeCommandMethod = .guestAgent
                        }
                    )
                }
            }
            .padding(14)
        }
        .onTapGesture {
            model.selectedVM = nil
            model.selectedIDs = []
        }
    }

    // MARK: List (native, multi-select)

    private var vmList: some View {
        List(selection: $model.selectedIDs) {
            ForEach(filteredVMs) { vm in
                VMListRow(
                    vm: vm,
                    density: density,
                    onStart: { model.pendingLaunchVM = vm },
                    onStop:  { model.confirmStop = vm },
                    onEdit:  { model.editingVM = vm },
                    onClone: { model.cloneVM = vm },
                    onDelete: { model.confirmDelete = vm },
                    onPin:   { vmStore.update(id: vm.id) { $0.isPinned.toggle() } },
                    onPush:  { model.pushVM = vm },
                    onExecSSH: {
                        model.executeCommandVM = vm
                        model.executeCommandMethod = .ssh
                    },
                    onExecGuestAgent: {
                        model.executeCommandVM = vm
                        model.executeCommandMethod = .guestAgent
                    },
                    onTagTap: { tag in
                        model.selectedTagFilters = [tag]
                    },
                    onTagShiftTap: { tag in
                        if model.selectedTagFilters.contains(tag) {
                            model.selectedTagFilters.remove(tag)
                        } else {
                            model.selectedTagFilters.insert(tag)
                        }
                    }
                )
                .tag(vm.id)
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: VirtualMachine.ID.self) { ids in
            bulkContextMenuItems(for: ids)
        } primaryAction: { ids in
            // Double-click / Return: open detail for single selection
            if ids.count == 1 {
                model.selectedIDs = ids
            }
        }
    }

    // MARK: Multi-selection context menu items

    @ViewBuilder
    private func bulkContextMenuItems(for ids: Set<VirtualMachine.ID>) -> some View {
        let vms = vmStore.vms.filter { ids.contains($0.id) }
        let count = ids.count
        if count >= 2 {
            Button("Start \(count) VMs") {
                let runningCount = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
                let toStart = Array(vms.filter { $0.status == .stopped }.prefix(max(0, 2 - runningCount)))
                guard !toStart.isEmpty else {
                    let names = vmStore.vms
                        .filter { $0.status == .running || $0.status == .suspended }
                        .map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                        .joined(separator: ", ")
                    model.macOSLimitError = "macOS allows at most 2 simultaneous VMs. Currently running: \(names)."
                    return
                }
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        for vm in toStart {
                            group.addTask {
                                let stream = await vmStore.start(vm: vm, mode: .native)
                                for await _ in stream {}
                            }
                        }
                    }
                    await vmStore.sync()
                }
            }
            Button("Stop \(count) VMs") {
                for vm in vms where vm.status == .running || vm.status == .suspended {
                    Task { try? await vmStore.stop(vm: vm) }
                }
            }
            Button("Suspend \(count) VMs") {
                for vm in vms where vm.status == .running {
                    Task { try? await vmStore.stop(vm: vm) }
                }
            }
            Divider()
            Button("Delete \(count) VMs…", role: .destructive) {
                model.selectedIDs = ids
                model.confirmBulkDelete = true
            }
        } else if let vm = vms.first {
            Button { model.pendingLaunchVM = vm } label: {
                Label(vm.status == .running || vm.status == .suspended ? "Stop…" : "Start…",
                      systemImage: vm.status == .running || vm.status == .suspended ? "stop.fill" : "play.fill")
            }
            if vm.status == .running || vm.status == .suspended {
                Button { model.confirmStop = vm } label: {
                    Label("Stop…", systemImage: "stop.fill")
                }
            }
            Divider()
            Button { model.editingVM = vm } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Button { model.cloneVM = vm } label: {
                Label("Clone…", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                vmStore.update(id: vm.id) { $0.isPinned.toggle() }
            } label: {
                Label(vm.isPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar",
                      systemImage: vm.isPinned ? "pin.slash" : "pin")
            }
            Button { model.pushVM = vm } label: {
                Label("Push to Registry…", systemImage: "arrow.up.circle")
            }
            .disabled(vm.status != .stopped)
            Divider()
            Button(role: .destructive) { model.confirmDelete = vm } label: {
                Label("Delete…", systemImage: "trash")
            }
        }
    }

    // MARK: Multi-selection summary pane

    private var multiSelectionSummary: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(model.selectedIDs.count) VMs Selected")
                .font(.headline)
            Text(selectedVMs.map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                    .joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Divider()

            BulkActionsMenu(
                count: model.selectedIDs.count,
                selectedVMs: selectedVMs,
                vmStore: vmStore,
                model: model
            )

            Button("Clear Selection") {
                model.selectedIDs.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: Empty state

    private var emptyState: some View {
        EmptyStateView("No Virtual Machines", systemImage: "desktopcomputer",
                       description: "Create a new VM from a Base VM or pull an image from a registry.") {
            Button("New VM") { appState.isPresentingNewVM = true }
                .buttonStyle(.borderedProminent)
        } content: { EmptyView() }
    }

    // MARK: Window title

    private func updateWindowTitle() {
        let selectedVM: VirtualMachine? = {
            if model.selectedIDs.count == 1 {
                return vmStore.vms.first { model.selectedIDs.contains($0.id) }
            }
            return model.selectedVM
        }()
        if let vm = selectedVM {
            let name = vm.displayName.isEmpty ? vm.name : vm.displayName
            appState.windowTitle = name
            appState.windowSubtitle = "Virtual Machines"
        } else {
            appState.windowTitle = "Virtual Machines"
            appState.windowSubtitle = ""
        }
    }

}

// MARK: - VMListSheets (extracted to help the type-checker)

private struct VMListSheets: ViewModifier {
    @Bindable var model: VMListViewModel
    let vmStore: VMStore
    let baseVMStore: BaseVMStore
    let appState: AppState
    let serverStore: MDMServerStore

    private var stopTitle: String {
        model.confirmStop.map { "Stop \($0.displayName.isEmpty ? $0.name : $0.displayName)?" } ?? "Stop VM?"
    }
    private var deleteTitle: String {
        model.confirmDelete.map { "Delete \"\($0.displayName.isEmpty ? $0.name : $0.displayName)\"?" } ?? "Delete VM?"
    }
    private var stopAllTitle: String {
        let count = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
        return "Stop \(count) Running VM\(count == 1 ? "" : "s")?"
    }

    /// Returns the Jamf server for a VM only when delete-from-Jamf is enabled and the VM has a serial number.
    private func jamfServer(for vm: VirtualMachine) -> MDMServer? {
        guard let serverID = vm.mdmServerID,
              let server = serverStore.servers.first(where: { $0.id == serverID }),
              server.featureDeleteFromJamf,
              !vm.serialNumber.isEmpty else { return nil }
        return server
    }

    private var bulkHasJamf: Bool {
        vmStore.vms.filter { model.selectedIDs.contains($0.id) }.contains { jamfServer(for: $0) != nil }
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(stopTitle,
                isPresented: Binding(get: { model.confirmStop != nil }, set: { if !$0 { model.confirmStop = nil } }),
                titleVisibility: .visible
            ) {
                Button("Stop", role: .destructive) {
                    if let vm = model.confirmStop {
                        model.confirmStop = nil
                        Task { try? await vmStore.stop(vm: vm) }
                    }
                }
                Button("Cancel", role: .cancel) { model.confirmStop = nil }
            } message: {
                Text("The VM will be sent a shutdown signal and given 30 seconds to stop gracefully.")
            }
            .sheet(item: $model.cloneVM) { vm in
                CloneVMSheet(vm: vm)
                    .environmentObject(vmStore)
                    .environmentObject(baseVMStore)
                    .environmentObject(appState)
            }
            .confirmationDialog(deleteTitle,
                isPresented: Binding(get: { model.confirmDelete != nil }, set: { if !$0 { model.confirmDelete = nil } }),
                titleVisibility: .visible
            ) {
                if let vm = model.confirmDelete, let server = jamfServer(for: vm) {
                    Button("Delete and Remove from Jamf", role: .destructive) {
                        model.confirmDelete = nil
                        Task { try? await vmStore.delete(vm: vm, mdmServer: server) }
                    }
                }
                Button("Delete", role: .destructive) {
                    guard let vmToDelete = model.confirmDelete else { return }
                    model.confirmDelete = nil
                    Task { try? await vmStore.delete(vm: vmToDelete) }
                }
                Button("Cancel", role: .cancel) { model.confirmDelete = nil }
            } message: {
                Text("This permanently removes the VM image from disk. This cannot be undone.")
            }
            .confirmationDialog("Delete \(model.selectedIDs.count) VMs?",
                isPresented: $model.confirmBulkDelete,
                titleVisibility: .visible
            ) {
                if bulkHasJamf {
                    Button("Delete \(model.selectedIDs.count) VMs and Remove from Jamf", role: .destructive) {
                        let ids = model.selectedIDs
                        model.selectedIDs.removeAll()
                        for vm in vmStore.vms where ids.contains(vm.id) {
                            Task { try? await vmStore.delete(vm: vm, mdmServer: jamfServer(for: vm)) }
                        }
                    }
                }
                Button("Delete \(model.selectedIDs.count) VMs", role: .destructive) {
                    let ids = model.selectedIDs
                    model.selectedIDs.removeAll()
                    for vm in vmStore.vms where ids.contains(vm.id) {
                        Task { try? await vmStore.delete(vm: vm) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes \(model.selectedIDs.count) VM images from disk. This cannot be undone.")
            }
            .sheet(isPresented: Binding(get: { appState.isPresentingNewVM }, set: { appState.isPresentingNewVM = $0 })) {
                NewVMSheet()
                    .environmentObject(vmStore)
                    .environmentObject(baseVMStore)
                    .environmentObject(appState)
            }
            .sheet(item: $model.pendingLaunchVM) { vm in
                LaunchModeSheet(vm: vm) { mode in
                    model.pendingLaunchVM = nil
                    Task { await startVM(vm, mode: mode, vmStore: vmStore, appState: appState) }
                }
            }
            .alert("Cannot Start VM", isPresented: Binding(
                get: { model.macOSLimitError != nil },
                set: { if !$0 { model.macOSLimitError = nil } }
            )) {
                Button("OK") { model.macOSLimitError = nil }
            } message: {
                Text(model.macOSLimitError ?? "")
            }
            .confirmationDialog(stopAllTitle,
                isPresented: $model.confirmStopAll,
                titleVisibility: .visible
            ) {
                Button("Stop All", role: .destructive) {
                    let running = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }
                    for vm in running {
                        Task { try? await vmStore.stop(vm: vm) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each VM will be sent a shutdown signal and given 30 seconds to stop gracefully.")
            }
            .sheet(item: $model.editingVM) { vm in
                VMEditSheet(vm: vm)
                    .environmentObject(vmStore)
            }
            .sheet(isPresented: Binding(
                get: { model.pushVM != nil },
                set: { if !$0 { model.pushVM = nil } }
            )) {
                if let vm = model.pushVM {
                    PushToRegistrySheet(vmName: vm.name) { imageRef, credentials in
                        model.pushVM = nil
                        Task { await pushVM(vm, to: imageRef, credentials: credentials) }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { model.executeCommandVM != nil },
                set: { if !$0 { model.executeCommandVM = nil } }
            )) {
                if let vm = model.executeCommandVM {
                    ExecuteCommandSheet(vm: vm, initialMethod: model.executeCommandMethod)
                }
            }
    }

    private func pushVM(_ vm: VirtualMachine, to imageRef: String, credentials: [RegistryCredential]) async {
        let tartPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else { return }
        let host = imageRef.components(separatedBy: "/").first ?? ""
        let cred = credentials.first(where: { $0.registry == host })
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartPath,
                                  registryUsername: cred?.username,
                                  registryPassword: cred?.password)
        let stream = await tartSvc.push(name: vm.name, to: imageRef)
        for await event in stream {
            if case .exit(let code) = event {
                if code == 0 {
                    AppLogger.shared.success("Push complete: \(imageRef)", source: "VMListView")
                } else {
                    AppLogger.shared.error("Push failed (exit \(code))", source: "VMListView")
                }
            }
        }
    }

    private func startVM(_ vmToStart: VirtualMachine, mode: TartService.RunMode, vmStore: VMStore, appState: AppState) async {
        guard !vmToStart.effectivelyBase else { return }
        let runningCount = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
        if runningCount >= 2 {
            let names = vmStore.vms
                .filter { $0.status == .running || $0.status == .suspended }
                .map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                .joined(separator: ", ")
            model.macOSLimitError = "macOS allows at most 2 simultaneous VMs. Currently running: \(names)."
            return
        }
        await model.startVM(vmToStart, mode: mode, vmStore: vmStore, appState: appState)
    }
}

// MARK: - Bulk Actions Menu

/// Shown in the toolbar and multi-selection summary pane when ≥2 VMs are selected.
struct BulkActionsMenu: View {
    let count: Int
    let selectedVMs: [VirtualMachine]
    let vmStore: VMStore
    @Bindable var model: VMListViewModel

    var body: some View {
        Menu {
            Button("Start All") {
                let runningCount = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
                let toStart = Array(selectedVMs.filter { $0.status == .stopped }.prefix(max(0, 2 - runningCount)))
                guard !toStart.isEmpty else {
                    let names = vmStore.vms
                        .filter { $0.status == .running || $0.status == .suspended }
                        .map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                        .joined(separator: ", ")
                    model.macOSLimitError = "macOS allows at most 2 simultaneous VMs. Currently running: \(names)."
                    return
                }
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        for vm in toStart {
                            group.addTask {
                                let stream = await vmStore.start(vm: vm, mode: .native)
                                for await _ in stream {}
                            }
                        }
                    }
                    await vmStore.sync()
                }
            }
            Button("Stop All") {
                for vm in selectedVMs where vm.status == .running || vm.status == .suspended {
                    Task { try? await vmStore.stop(vm: vm) }
                }
            }
            Button("Suspend All") {
                for vm in selectedVMs where vm.status == .running {
                    Task { try? await vmStore.stop(vm: vm) }
                }
            }
            Divider()
            Button("Delete…", role: .destructive) {
                model.confirmBulkDelete = true
            }
        } label: {
            Label("\(count) selected", systemImage: "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - VMListRow (list-mode row using VMCard visuals)

/// A compact list row that mirrors VMCard's status dot, name, tags, meta row and status pill
/// without the thumbnail. Vertical padding is driven by `density`.
struct VMListRow: View {
    let vm: VirtualMachine
    let density: ListDensity
    let onStart: () -> Void
    let onStop:  () -> Void
    let onEdit:  () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void
    var onPin:  (() -> Void)? = nil
    var onPush: (() -> Void)? = nil
    var onExecSSH: (() -> Void)? = nil
    var onExecGuestAgent: (() -> Void)? = nil
    var onTagTap: ((String) -> Void)? = nil
    var onTagShiftTap: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: vm.status)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vm.displayName.isEmpty ? vm.name : vm.displayName)
                        .fontWeight(.medium)
                    Text(vm.status.label)
                        .font(.caption)
                        .foregroundStyle(statusCaptionColor)
                }
                HStack(spacing: 4) {
                    if vm.osName != .unknown {
                        Text(vm.osName.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                        if !vm.osVersion.isEmpty {
                            Text(vm.osVersion)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !vm.osVersion.isEmpty {
                        Text(vm.osVersion)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(vm.tags.prefix(3).enumerated()), id: \.offset) { _, tag in
                        TagChip(tag: tag, size: .caption2,
                                onTap: onTagTap,
                                onShiftTap: onTagShiftTap)
                    }
                }
                .frame(height: 16)
            }
            Spacer()
            Menu {
                if vm.status == .running || vm.status == .suspended {
                    Button { onStop() } label: { Label("Stop…", systemImage: "stop.fill") }
                } else {
                    Button { onStart() } label: { Label("Start…", systemImage: "play.fill") }
                }
                Divider()
                Button { onEdit() } label: { Label("Edit…", systemImage: "pencil") }
                Button { onClone() } label: { Label("Clone…", systemImage: "doc.on.doc") }
                Divider()
                Button { onPin?() } label: {
                    Label(vm.isPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar",
                          systemImage: vm.isPinned ? "pin.slash" : "pin")
                }
                Button { onPush?() } label: {
                    Label("Push to Registry…", systemImage: "arrow.up.circle")
                }
                .disabled(vm.status != .stopped)
                if vm.status == .running {
                    Divider()
                    Button {
                        onExecSSH?()
                    } label: {
                        Label("Execute via SSH…", systemImage: "terminal")
                    }
                    .disabled(vm.ipAddress == nil)
                    if vm.supportsGuestAgent {
                        Button { onExecGuestAgent?() } label: {
                            Label("Execute via Guest Agent…", systemImage: "bolt.horizontal.circle")
                        }
                    }
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, density.verticalPadding / 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        let name = vm.displayName.isEmpty ? vm.name : vm.displayName
        let tags = vm.tags.isEmpty ? "" : ", tags: \(vm.tags.prefix(3).joined(separator: ", "))"
        return "\(vm.status.label): \(name)\(tags)"
    }

    private var statusCaptionColor: Color {
        switch vm.status {
        case .running:   return .green
        case .error:     return .red
        case .building:  return .vmBuilding
        default:         return .secondary
        }
    }
}

// MARK: - VM Card


// MARK: - Status dot


// MARK: - Detail Pane



// MARK: - Push to Registry sheet

/// Parse tart push errors — same format as pull errors.


// MARK: - Clone VM sheet
