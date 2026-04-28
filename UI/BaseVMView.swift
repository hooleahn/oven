import SwiftUI

// MARK: - BaseVMView

struct BaseVMView: View {
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var templateStore: PackerTemplateStore
    @EnvironmentObject var blockStore: BuildingBlockStore
    @EnvironmentObject var pushManager: PushManager
    @State private var lastRefreshedAt: Date? = nil
    @State private var isRefreshing: Bool = false
    @State private var refreshRotation: Double = 0

    private func coarseAge(of date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 120     { return "just now" }
        if s < 3600    { return "\(s / 60) min ago" }
        if s < 86_400  { return "\(s / 3600) hr ago" }
        return "\(s / 86_400)d ago"
    }
    private let buildSession = BuildSessionManager.shared
    /// Model is owned by ContentView so the detail column can also access it.
    @Bindable var model: BaseVMViewModel
    @State private var searchText: String = ""

    init(model: BaseVMViewModel) {
        self.model = model
    }

    /// Always read the live version from the store so build log updates propagate
    var selectedBaseVM: VirtualMachine? {
        guard let id = model.selectedBaseVMID else { return nil }
        return baseVMStore.baseVMs.first { $0.id == id }
    }

    var localVMs: [VirtualMachine] {
        let vms = baseVMStore.baseVMs.filter { $0.vmSource == .local && !$0.name.contains("/") }
        guard !searchText.isEmpty else { return vms }
        let q = searchText.lowercased()
        return vms.filter { $0.name.localizedCaseInsensitiveContains(q)
                          || $0.displayName.localizedCaseInsensitiveContains(q)
                          || $0.description.localizedCaseInsensitiveContains(q)
                          || $0.macOSVersion.localizedCaseInsensitiveContains(q)
                          || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) }
    }

    var registryVMs: [VirtualMachine] {
        let vms = baseVMStore.baseVMs.filter { $0.vmSource == .registry || $0.name.contains("/") }
        guard !searchText.isEmpty else { return vms }
        let q = searchText.lowercased()
        return vms.filter { $0.name.localizedCaseInsensitiveContains(q)
                          || $0.displayName.localizedCaseInsensitiveContains(q)
                          || $0.description.localizedCaseInsensitiveContains(q)
                          || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) }
    }

    var body: some View {
        // ── Content column: list only ──────────────────────────────────────
        // The detail pane lives in ContentView's detail column, not here.
        listColumn
        .navigationTitle(theme.baseVMs)
        .task { updateWindowTitle() }
        .onChange(of: model.selectedBaseVMID) { _, id in
            // Sync selection to appState so ContentView's detail column can render it.
            appState.selectedBaseVMID = id
            updateWindowTitle()
        }
        .searchable(text: $searchText, prompt: "Search Base VMs…")
        .toolbar {
            // 1. Navigation group (empty)
            ToolbarItemGroup(placement: .navigation) {}

            // 2. Primary action — New Base VM (⌘N)
            ToolbarItem(placement: .primaryAction) {
                Button { model.isPresentingNewSheet = true } label: {
                    Label(theme.newBaseVM, systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("\(theme.newBaseVM) (⌘N)")
            }

            // 3. Secondary actions
            ToolbarItemGroup(placement: .secondaryAction) {
                if baseVMStore.isBuilding {
                    Text("\(theme.building)…").font(.callout).foregroundStyle(.secondary)
                    Button {
                        if buildSession.isLocked {
                            BuildSessionManager.shared.disableInputLock()
                        } else {
                            BuildSessionManager.shared.enableInputLock()
                        }
                    } label: {
                        Label(buildSession.isLocked ? "Unlock Input" : "Lock Input",
                              systemImage: buildSession.isLocked ? "lock.fill" : "lock.open")
                    }
                    .help(buildSession.isLocked ? "Unlock keyboard & mouse (⌘⇧⎋)" : "Lock keyboard & mouse during build")
                    Button("Cancel") { baseVMStore.cancelBuild() }
                }

                // Clone selected Base VM as a Working VM (⌘D)
                if let selected = model.selectedBaseVM(from: baseVMStore.baseVMs),
                   selected.buildStatus == .ready {
                    Button { model.createVMFromBase = selected } label: {
                        Label("Clone as Working VM", systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .help("Create a working VM from this base VM (⌘D)")
                }

                // Delete selected (⌘⌫)
                if let selected = model.selectedBaseVM(from: baseVMStore.baseVMs) {
                    Button(role: .destructive) { model.confirmDelete = selected } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete selected base VM (⌘⌫)")
                    .disabled(selected.status == .building)
                }
            }

            // 4. Flexible space
            ToolbarItem(placement: .automatic) {
                Spacer()
            }

            // 5. Search is provided by .searchable

            // 6. Last-synced label (no sort menu for base VMs)
            ToolbarItem(placement: .automatic) {
                if let refreshed = lastRefreshedAt {
                    Text("Synced " + coarseAge(of: refreshed))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8)
                }
            }

            // 7. Refresh (⌘R)
            ToolbarItem(placement: .automatic) {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        refreshRotation = 360
                    }
                    Task {
                        await baseVMStore.syncOCI()
                        lastRefreshedAt = Date()
                        isRefreshing = false
                        refreshRotation = 0
                    }
                } label: {
                    Label("Refresh Base VMs", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh base VM list (⌘R)")
            }
        }
        .task { await baseVMStore.syncOCI(); lastRefreshedAt = Date() }
        .overlay {
            if buildSession.isLocked {
                InputLockedOverlay()
            }
        }
        .confirmationDialog(
            model.confirmDelete.map { "Delete \"\($0.displayName.isEmpty ? $0.name : $0.displayName)\"?" } ?? "Delete Base VM?",
            isPresented: Binding(get: { model.confirmDelete != nil }, set: { if !$0 { model.confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let vmToDelete = model.confirmDelete,
                      vmToDelete.status != .building else {
                    model.confirmDelete = nil
                    return
                }
                let deletedID = vmToDelete.id
                model.confirmDelete = nil
                Task {
                    await baseVMStore.delete(id: deletedID)
                    if model.selectedBaseVMID == deletedID { model.selectedBaseVMID = nil }
                }
            }
            Button("Cancel", role: .cancel) { model.confirmDelete = nil }
        } message: {
            Text("This permanently removes the base VM image from disk. This cannot be undone.")
        }
        .onChange(of: baseVMStore.baseVMs) { _, vms in
            Task { @MainActor in
                if let id = self.model.selectedBaseVMID, !vms.contains(where: { $0.id == id }) {
                    self.model.selectedBaseVMID = nil
                }
            }
        }
        .sheet(isPresented: $model.isPresentingNewSheet) {
            NewBaseVMSheet()
                .environmentObject(baseVMStore)
                .environmentObject(theme)
                .environmentObject(templateStore)
                .environmentObject(blockStore)
        }
        .sheet(item: $model.createVMFromBase) { base in
            NewVMFromBaseSheet(baseVM: base)
        }
        .sheet(item: $model.editingBaseVM) { vm in
            BaseVMEditSheet(baseVM: vm)
                .environmentObject(baseVMStore)
                .environmentObject(vmStore)
                .environmentObject(templateStore)
        }
        .sheet(isPresented: Binding(
            get: { model.pushToRegistryBaseVM != nil },
            set: { if !$0 { model.pushToRegistryBaseVM = nil } }
        )) {
            if let vm = model.pushToRegistryBaseVM {
                PushToRegistrySheet(vmName: vm.name) { imageRef, credentials in
                    model.pushToRegistryBaseVM = nil
                    let tartPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/tart").path
                    Task { await pushManager.push(baseVM: vm, to: imageRef,
                                                  credentials: credentials, tartPath: tartPath) }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.showBuildLogForBaseVM != nil },
            set: { if !$0 { model.showBuildLogForBaseVM = nil } }
        )) {
            if let vm = model.showBuildLogForBaseVM {
                BuildLogWindow(baseVM: vm)
            }
        }
    }

    @ViewBuilder private var listColumn: some View {
        VStack(spacing: 0) {
            if baseVMStore.baseVMs.isEmpty { emptyState } else { list }
            if baseVMStore.isBuilding,
               let buildingVM = baseVMStore.baseVMs.first(where: { $0.status == .building }) {
                Divider()
                LiveBuildLogPanel(baseVM: buildingVM)
            }
        }
    }

    private var list: some View {
        List(selection: $model.selectedBaseVMID) {
            if !localVMs.isEmpty {
                Section("Local") {
                    ForEach(localVMs) { vm in
                        BaseVMRow(vm: vm, theme: theme)
                            .tag(vm.id)
                            .contextMenu { baseVMContextMenu(for: vm) }
                    }
                }
            }
            if !registryVMs.isEmpty {
                Section("Registry") {
                    ForEach(registryVMs) { vm in
                        BaseVMRow(vm: vm, theme: theme)
                            .tag(vm.id)
                            .contextMenu { baseVMContextMenu(for: vm) }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func baseVMContextMenu(for vm: VirtualMachine) -> some View {
        Button { model.selectedBaseVMID = vm.id } label: {
            Label("Show Details", systemImage: "info.circle")
        }
        if vm.buildStatus == .ready {
            Button { model.createVMFromBase = vm } label: {
                Label("Clone as VM", systemImage: "doc.on.doc")
            }
        }
        Divider()
        Button { model.editingBaseVM = vm } label: {
            Label("Edit…", systemImage: "pencil")
        }
        Button { model.showBuildLogForBaseVM = vm } label: {
            Label("Show Build Log", systemImage: "terminal")
        }
        if vm.buildStatus == .ready && vm.vmSource == .local {
            Button { model.pushToRegistryBaseVM = vm } label: {
                Label("Push to Registry…", systemImage: "arrow.up.circle")
            }
        }
        Divider()
        Button(role: .destructive) { model.confirmDelete = vm } label: {
            Label("Delete…", systemImage: "trash")
        }
        .disabled(vm.buildStatus == .building)
    }

    private var emptyState: some View {
        EmptyStateView(
            theme.baseVMs,
            systemImage: theme.baseVMIcon,
            description: theme.funModeEnabled
                ? "No recipes yet. Bake a new one to get started."
                : "Build a base VM with Packer to start cloning from it."
        ) {
            Button(theme.newBaseVM) { model.isPresentingNewSheet = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Window title

    private func updateWindowTitle() {
        if let vm = selectedBaseVM {
            let name = vm.displayName.isEmpty ? vm.name : vm.displayName
            appState.windowTitle = name
            appState.windowSubtitle = theme.baseVMs
        } else {
            appState.windowTitle = theme.baseVMs
            appState.windowSubtitle = ""
        }
    }
}


// MARK: - Row


// MARK: - Detail pane


// MARK: - Build Log View


// MARK: - New Base VM Sheet


// MARK: - Input Locked Overlay


// MARK: - Live Build Log Panel

// Shared log-line colouring based on actual packer output format.
func buildLogLineColor(_ line: String) -> Color {
    // Our explicit error prefix (only added for genuine errors)
    if line.hasPrefix("[err]") || line.hasPrefix("✗") { return .red }
    // Packer's build-failure summary
    if line.hasPrefix("Build '") && line.contains("errored") { return .red }
    // Packer progress headers ("==> tart-cli.tart: ...")
    if line.hasPrefix("==>") { return .primary }
    // Our success marker / packer build success
    if line.hasPrefix("✓") { return .green }
    if line.hasPrefix("Build '") && line.contains("finished") { return .green }
    // Packer build success arrow line
    if line.hasPrefix("--> ") { return .green }
    // Our warning marker
    if line.hasPrefix("⚠️") { return .orange }
    // Our command marker — show slightly brighter than debug
    if line.hasPrefix("[cmd]") { return Color.secondary.opacity(0.8) }
    // Our debug marker
    if line.hasPrefix("[debug]") { return Color.secondary.opacity(0.4) }
    // Packer verbose log lines: start with "2026/..." timestamp or plugin name
    // These are informational — show very dim so ==> lines stand out
    let isVerboseLine = line.first?.isNumber == true  // timestamp lines start with digit
        || line.hasPrefix("packer-")
        || line.hasPrefix("tart-cli.tart: output")
    if isVerboseLine { return Color.secondary.opacity(0.35) }
    return .secondary
}



// MARK: - NewVMFromBaseSheet

/// Thin sheet wrapper that opens NewVMSheet pre-selecting a specific base VM.
struct NewVMFromBaseSheet: View {
    let baseVM: VirtualMachine
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        NewVMSheet(preselectedBase: baseVM)
            .environmentObject(baseVMStore)
            .environmentObject(appState)
    }
}

// MARK: - BaseVMEditSheet

