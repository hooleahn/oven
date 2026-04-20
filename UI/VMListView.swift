import SwiftUI
import AppKit

// MARK: - VMListView

struct VMListView: View {
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serverStore: MDMServerStore
    @State private var model = VMListViewModel()



    /// All tags across all VMs for filter picker and autocomplete
    var filteredVMs: [VirtualMachine] {
        model.filteredVMs(from: vmStore.vms, searchQuery: appState.searchQuery)
    }
    private var workingVMs: [VirtualMachine] { vmStore.vms.filter { !$0.effectivelyBase } }
    var allTags: [String]     { model.allTags(from: workingVMs) }
    var allOSMajors: [String] { model.allOSMajors(from: workingVMs) }
    func osVersions(under major: String) -> [String] { model.osVersions(under: major, from: workingVMs) }

    var body: some View {
        HStack(spacing: 0) {
            // ── Main list ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                toolbar
                Divider()
                if vmStore.vms.isEmpty && !vmStore.isSyncing {
                    emptyState
                } else if model.isListView {
                    vmList
                } else {
                    vmGrid
                }
            }

            // ── Detail pane ────────────────────────────────────────────────
            if let vm = model.selectedVM {
                Divider()
                VMDetailPane(vm: vm, onDismiss: { model.selectedVM = nil },
                             onStart: { Task { await startVM(vm) } })
                    .environmentObject(baseVMStore)
                    .environmentObject(serverStore)
                    .frame(width: 260)
            }
        }
        .navigationTitle("Virtual Machines")
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
        .sheet(isPresented: $appState.isPresentingNewVM) {
            NewVMSheet()
                .environmentObject(vmStore)
                .environmentObject(baseVMStore)
                .environmentObject(appState)
        }
        .searchable(text: $appState.searchQuery, prompt: "Search VMs…")
        .task { await vmStore.sync() }
        .refreshable { await vmStore.sync() }
        .onChange(of: vmStore.vms) { _, vms in
            Task { @MainActor in
                if let id = self.model.selectedVM?.id {
                    self.model.selectedVM = vms.first { $0.id == id }
                }
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

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Tab filter
            Picker("", selection: $model.selectedTab) {
                ForEach(VMTab.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Spacer()

            // Sync indicator
            if vmStore.isSyncing {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await vmStore.sync() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh VM list")

            // ── Filters + Sort ───────────────────────────────────────────────
            HStack(spacing: 4) {
                tagFilterMenu
                osFilterMenu
                sortMenu
            }
            .fixedSize()

            Button { model.isListView.toggle() } label: {
                Image(systemName: model.isListView ? "square.grid.2x2" : "list.bullet")
            }
            .help(model.isListView ? "Switch to grid view" : "Switch to list view")

            // Stop All — only shown when VMs are running
            let runningVMs = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }
            if !runningVMs.isEmpty {
                Button {
                    model.confirmStopAll = true
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .help("Stop all \(runningVMs.count) running VM\(runningVMs.count == 1 ? "" : "s")")
            }

            Button {
                appState.isPresentingNewVM = true
            } label: {
                Label("New VM", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
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
                            Circle().fill(tagColor(for: tag)).frame(width: 8, height: 8)
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

    /// Combined filters menu for narrow toolbar
    @ViewBuilder private var collapsedMenu: some View {
        let activeCount = model.selectedTagFilters.count + model.selectedOSFilters.count
        Menu {
            if activeCount > 0 {
                Button("Clear all filters") {
                    model.selectedTagFilters.removeAll(); model.selectedOSFilters.removeAll()
                }
                Divider()
            }
            if !allTags.isEmpty {
                Section("Tags") {
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            if model.selectedTagFilters.contains(tag) { model.selectedTagFilters.remove(tag) }
                            else { model.selectedTagFilters.insert(tag) }
                        } label: {
                            HStack {
                                Circle().fill(tagColor(for: tag)).frame(width: 8, height: 8)
                                Text(tag)
                                if model.selectedTagFilters.contains(tag) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            if !allOSMajors.isEmpty {
                Section("OS") {
                    ForEach(allOSMajors, id: \.self) { major in
                        ForEach(osVersions(under: major), id: \.self) { ver in
                            Button {
                                if model.selectedOSFilters.contains(ver) { model.selectedOSFilters.remove(ver) }
                                else { model.selectedOSFilters.insert(ver) }
                            } label: {
                                HStack {
                                    Text(ver)
                                    if model.selectedOSFilters.contains(ver) { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease")
                if activeCount > 0 { badgeView(activeCount) }
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .help(activeCount == 0 ? "Filter" : "\(activeCount) filter(s) active")
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

    // MARK: List

    private func makeVMListSelectionBinding() -> Binding<VirtualMachine.ID?> {
        Binding(
            get: { model.selectedVM?.id },
            set: { id in
                Task { @MainActor in self.model.selectedVM = self.vmStore.vms.first { $0.id == id } }
            }
        )
    }

    @ViewBuilder
    private func vmListRow(_ vm: VirtualMachine) -> some View {
        HStack(spacing: 10) {
            StatusDot(status: vm.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.displayName.isEmpty ? vm.name : vm.displayName)
                    .fontWeight(.medium)
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
                        TagChip(tag: tag, size: 9)
                    }
                }
                .frame(height: 16)
            }
            Spacer()
            StatusPill(status: vm.status)
            Menu {
                Button("Start…") { model.pendingLaunchVM = vm }
                Button("Stop…") { model.confirmStop = vm }
                    .disabled(vm.status == .stopped)
                Divider()
                Button("Edit…") { model.editingVM = vm }
                Button("Delete…", role: .destructive) { model.confirmDelete = vm }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .tag(vm.id)
    }

    private var vmList: some View {
        List(selection: makeVMListSelectionBinding()) {
            ForEach(filteredVMs) { vm in
                vmListRow(vm)
            }
        }
        .listStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        EmptyStateView("No Virtual Machines", systemImage: "desktopcomputer",
                       description: "Create a new VM from a Base VM or pull an image from a registry.") {
            Button("New VM") { appState.isPresentingNewVM = true }
                .buttonStyle(.borderedProminent)
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

// MARK: - VM Card


// MARK: - Status dot


// MARK: - Detail Pane



// MARK: - Push to Registry sheet

/// Parse tart push errors — same format as pull errors.


// MARK: - Clone VM sheet
