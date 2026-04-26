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
        model.filteredVMs(from: vmStore.vms, searchQuery: appState.searchQuery)
    }
    private var workingVMs: [VirtualMachine] { vmStore.vms.filter { !$0.effectivelyBase } }
    var allTags: [String]     { model.allTags(from: workingVMs) }
    var allOSMajors: [String] { model.allOSMajors(from: workingVMs) }
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
        .navigationTitle("Virtual Machines")
        .task { updateWindowTitle() }
        .onChange(of: model.selectedIDs, initial: false) { _, newIDs in
            // Sync single selection to appState so the detail column can render it.
            appState.selectedVMID = newIDs.count == 1 ? newIDs.first : nil
            updateWindowTitle()
        }
        .onChange(of: model.selectedVM, initial: false) { _, vm in
            // Grid mode single-selection.
            appState.selectedVMID = vm?.id
            updateWindowTitle()
        }
        .confirmationDialog(
            model.confirmStop.map { "Stop \($0.displayName.isEmpty ? $0.name : $0.displayName)?" } ?? "Stop VM?",
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
        .confirmationDialog(
            "Delete \"\(model.confirmDelete?.displayName ?? "")\"?",
            isPresented: Binding(get: { model.confirmDelete != nil }, set: { if !$0 { model.confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let vmToDelete = model.confirmDelete else { return }
                model.confirmDelete = nil
                Task { try? await vmStore.delete(vm: vmToDelete) }
            }
        } message: {
            Text("This will permanently delete the VM image from disk. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete \(model.selectedIDs.count) VMs?",
            isPresented: $model.confirmBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(model.selectedIDs.count) VMs", role: .destructive) {
                let ids = model.selectedIDs
                model.selectedIDs.removeAll()
                for vm in vmStore.vms where ids.contains(vm.id) {
                    Task { try? await vmStore.delete(vm: vm) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(model.selectedIDs.count) VM images from disk. This cannot be undone.")
        }
        .sheet(isPresented: $appState.isPresentingNewVM) {
            NewVMSheet()
                .environmentObject(vmStore)
                .environmentObject(baseVMStore)
                .environmentObject(appState)
        }
        .searchable(text: $appState.searchQuery, prompt: "Search VMs…")
        .toolbar {
            // 1. Navigation group (empty — no back/forward in this view)
            ToolbarItemGroup(placement: .navigation) {}

            // 2. Primary action — New VM (⌘N)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isPresentingNewVM = true
                } label: {
                    Label("New VM", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New VM (⌘N)")
            }

            // 3. Secondary actions
            ToolbarItemGroup(placement: .secondaryAction) {
                // Bulk actions when 2+ VMs selected in list mode
                if model.isListView && model.selectedIDs.count >= 2 {
                    BulkActionsMenu(
                        count: model.selectedIDs.count,
                        selectedVMs: selectedVMs,
                        vmStore: vmStore,
                        model: model
                    )
                }

                // Clone selected VM (⌘D)
                if model.selectedIDs.count == 1,
                   let vm = vmStore.vms.first(where: { model.selectedIDs.contains($0.id) }) {
                    Button { model.cloneVM = vm } label: {
                        Label("Clone", systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .help("Clone selected VM (⌘D)")
                }

                // Delete selected (⌘⌫)
                if model.selectedIDs.count == 1,
                   let vm = vmStore.vms.first(where: { model.selectedIDs.contains($0.id) }) {
                    Button(role: .destructive) { model.confirmDelete = vm } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete selected VM (⌘⌫)")
                } else if model.selectedIDs.count >= 2 {
                    Button(role: .destructive) { model.confirmBulkDelete = true } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete selected VMs (⌘⌫)")
                }

                // Stop All — only shown when VMs are running
                let runningVMs = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }
                if !runningVMs.isEmpty {
                    Button {
                        model.confirmStopAll = true
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                    }
                    .tint(.red)
                    .help("Stop all \(runningVMs.count) running VM\(runningVMs.count == 1 ? "" : "s")")
                }
            }

            // 4. Flexible space
            ToolbarItem(placement: .automatic) {
                Spacer()
            }

            // 5. Search is provided by .searchable — no explicit item needed

            // 6. Sort / filter / view-mode menus
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    tagFilterMenu
                    osFilterMenu
                    sortMenu

                    // View mode toggle
                    Button { model.isListView.toggle() } label: {
                        Image(systemName: model.isListView ? "square.grid.2x2" : "list.bullet")
                    }
                    .help(model.isListView ? "Switch to grid view" : "Switch to list view")

                    if model.isListView {
                        densityMenu
                    }

                    // Tab filter
                    Picker("", selection: $model.selectedTab) {
                        ForEach(VMTab.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
            }

            // 7. Refresh (⌘R) — always visible, animates when refreshing
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
//                    Label("Refresh", systemImage: "arrow.clockwise")
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh VM list (⌘R)")
            }
        }
        .task { await vmStore.sync() }
        .refreshable { await vmStore.sync() }
        .onChange(of: vmStore.vms) { _, vms in
            Task { @MainActor in
                // Keep grid single-selection in sync
                if let id = self.model.selectedVM?.id {
                    self.model.selectedVM = vms.first { $0.id == id }
                }
                // Prune stale IDs from multi-selection
                let validIDs = Set(vms.map { $0.id })
                self.model.selectedIDs = self.model.selectedIDs.intersection(validIDs)
            }
        }
        .sheet(item: $model.pendingLaunchVM) { vm in
            LaunchModeSheet(vm: vm) { mode in
                model.pendingLaunchVM = nil
                Task { await startVM(vm, mode: mode) }
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
        .confirmationDialog(
            "Stop All Running VMs?",
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
            let count = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
            Text("This will stop \(count) VM\(count == 1 ? "" : "s").")
        }
        .sheet(item: $model.editingVM) { vm in
            VMEditSheet(vm: vm)
                .environmentObject(vmStore)
        }

    }

    // MARK: Density menu

    @ViewBuilder private var densityMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: density.systemImage)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .help("Row density: \(density.rawValue)")
    }

    // MARK: Filter/Sort menus

    @ViewBuilder private var tagFilterMenu: some View {
        if !allTags.isEmpty {
            Menu {
                if !model.selectedTagFilters.isEmpty {
                    Button("Clear") { model.selectedTagFilters.removeAll() }
                    Divider()
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
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tag")
                    if !model.selectedTagFilters.isEmpty {
                        badgeView(model.selectedTagFilters.count)
                    }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help(model.selectedTagFilters.isEmpty ? "Filter by tag" : "\(model.selectedTagFilters.count) tag filter(s) active")
        }
    }

    @ViewBuilder private var osFilterMenu: some View {
        if !allOSMajors.isEmpty {
            Menu {
                if !model.selectedOSFilters.isEmpty {
                    Button("Clear") { model.selectedOSFilters.removeAll() }
                    Divider()
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
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "apple.logo")
                    if !model.selectedOSFilters.isEmpty { badgeView(model.selectedOSFilters.count) }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help(model.selectedOSFilters.isEmpty ? "Filter by OS" : "\(model.selectedOSFilters.count) OS filter(s) active")
        }
    }

    @ViewBuilder private var sortMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered).controlSize(.small)
        .help("Sort by: \(model.sortOrder.rawValue)")
    }

    // MARK: Active tag filter bar

    @ViewBuilder private var activeTagFilterBar: some View {
        if !model.selectedTagFilters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(model.selectedTagFilters.sorted(), id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                            Button {
                                model.selectedTagFilters.remove(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
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
                    .font(.system(size: 11))
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
                        onSelect: { model.selectedVM = (model.selectedVM?.id == vm.id) ? nil : vm },
                        onStart: { model.pendingLaunchVM = vm },
                        onStop:  { model.confirmStop = vm },
                        onEdit:  { model.editingVM = vm },
                        onClone: { model.cloneVM = vm },
                        onDelete: { model.confirmDelete = vm }
                    )
                }
            }
            .padding(14)
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
                for vm in vms where vm.status == .stopped {
                    Task {
                        let stream = await vmStore.start(vm: vm, mode: .native)
                        for await _ in stream {}
                        await vmStore.sync()
                    }
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
            Button("Start…") { model.pendingLaunchVM = vm }
            Button("Stop…") { model.confirmStop = vm }
                .disabled(vm.status == .stopped)
            Divider()
            Button("Edit…") { model.editingVM = vm }
            Button("Clone…") { model.cloneVM = vm }
            Button("Delete…", role: .destructive) { model.confirmDelete = vm }
        }
    }

    // MARK: Multi-selection summary pane

    private var multiSelectionSummary: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .light))
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

    // MARK: Actions

    private func startVM(_ vmToStart: VirtualMachine, mode: TartService.RunMode = .native) async {
        guard !vmToStart.effectivelyBase else { return }  // base VMs cannot be started
        // macOS limits concurrent macOS VMs to 2. Check before handing off to tart
        // so we give a clear error rather than letting tart exit with code 1.
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
                for vm in selectedVMs where vm.status == .stopped {
                    Task {
                        let stream = await vmStore.start(vm: vm, mode: .native)
                        // drain the stream; we don't show per-VM logs in bulk mode
                        for await _ in stream {}
                        await vmStore.sync()
                    }
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
                        TagChip(tag: tag, size: 9,
                                onTap: onTagTap,
                                onShiftTap: onTagShiftTap)
                    }
                }
                .frame(height: 16)
            }
            Spacer()
            Menu {
                Button("Start…") { onStart() }
                Button("Stop…") { onStop() }
                    .disabled(vm.status == .stopped)
                Divider()
                Button("Edit…") { onEdit() }
                Button("Clone…") { onClone() }
                Button("Delete…", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, density.verticalPadding / 2)
    }

    private var statusCaptionColor: Color {
        switch vm.status {
        case .running:   return .green
        case .error:     return .red
        case .building:  return .accentColor
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
