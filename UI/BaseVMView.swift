import SwiftUI

// MARK: - BaseVMView

struct BaseVMView: View {
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var templateStore: PackerTemplateStore
    @EnvironmentObject var blockStore: BuildingBlockStore
    @State private var lastRefreshedAt: Date? = nil

    private func coarseAge(of date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 120     { return "just now" }
        if s < 3600    { return "\(s / 60) min ago" }
        if s < 86_400  { return "\(s / 3600) hr ago" }
        return "\(s / 86_400)d ago"
    }
    private var buildSession = BuildSessionManager.shared
    @State private var model = BaseVMViewModel()
    @State private var searchText: String = ""

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
        HStack(spacing: 0) {
            listColumn
            detailColumn
        }
        .navigationTitle(theme.baseVMs)
        .searchable(text: $searchText, prompt: "Search Base VMs…")
        .task { await baseVMStore.syncOCI(); lastRefreshedAt = Date() }
        .overlay {
            if buildSession.isLocked {
                InputLockedOverlay()
            }
        }
        .confirmationDialog(
            "Delete \"\(model.confirmDelete?.name ?? "")\"?",
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
    }

    @ViewBuilder private var listColumn: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if baseVMStore.baseVMs.isEmpty { emptyState } else { list }
            if baseVMStore.isBuilding,
               let buildingVM = baseVMStore.baseVMs.first(where: { $0.status == .building }) {
                Divider()
                LiveBuildLogPanel(baseVM: buildingVM)
            }
        }
    }

    @ViewBuilder private var detailColumn: some View {
        if let selected = selectedBaseVM {
            Divider()
            BaseVMDetailPane(
                baseVM: selected,
                onBuild:    { Task { await baseVMStore.build(baseVM: selected) } },
                onDelete:   { model.confirmDelete = selected },
                onCreateVM: { model.createVMFromBase = selected }
            )
            .frame(width: 280)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            if baseVMStore.isBuilding {
                ProgressView().controlSize(.small)
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
                .buttonStyle(.bordered).controlSize(.small)
                .help(buildSession.isLocked ? "Unlock keyboard & mouse (⌘⇧⎋)" : "Lock keyboard & mouse during build")
                Button("Cancel") { baseVMStore.cancelBuild() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            // Show Clone button when a ready base VM is selected
            if let selected = model.selectedBaseVM(from: baseVMStore.baseVMs),
               selected.buildStatus == .ready {
                Button { model.createVMFromBase = selected } label: {
                    Label("Clone as Working VM", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Create a working VM from this base VM")
            }

            Button { Task { await baseVMStore.syncOCI(); lastRefreshedAt = Date() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Sync base VMs from tart")
            if let refreshed = lastRefreshedAt {
                Text("Synced · " + coarseAge(of: refreshed))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button { model.isPresentingNewSheet = true } label: {
                Label(theme.newBaseVM, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .help(theme.newBaseVM)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    private var list: some View {
        List(selection: $model.selectedBaseVMID) {
            if !localVMs.isEmpty {
                Section("Local") {
                    ForEach(localVMs) { vm in
                        BaseVMRow(vm: vm, theme: theme)
                            .tag(vm.id)
                            .contextMenu {
                                if vm.buildStatus == .ready {
                                    Button { model.createVMFromBase = vm } label: {
                                        Label("Clone as Working VM", systemImage: "doc.on.doc")
                                    }
                                }
                                Button { model.selectedBaseVMID = vm.id } label: {
                                    Label("Show Details", systemImage: "info.circle")
                                }
                            }
                    }
                }
            }
            if !registryVMs.isEmpty {
                Section("Registry") {
                    ForEach(registryVMs) { vm in
                        BaseVMRow(vm: vm, theme: theme)
                            .tag(vm.id)
                            .contextMenu {
                                Button { model.createVMFromBase = vm } label: {
                                    Label("Clone as Working VM", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
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
        } content: {
            BaseVMWorkflowIndicator()
        }
    }
}

// MARK: - Base VM workflow indicator (used in empty state)

private struct BaseVMWorkflowIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            WorkflowStep(icon: "arrow.down.circle.fill", color: .blue, label: "Download\nInstaller")
            WorkflowArrow()
            WorkflowStep(icon: "hammer.fill", color: .orange, label: "Build\nBase VM")
            WorkflowArrow()
            WorkflowStep(icon: "doc.on.doc.fill", color: .green, label: "Clone as\nWorking VM")
        }
        .padding(.vertical, 4)
    }
}

private struct WorkflowStep: View {
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }
}

private struct WorkflowArrow: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 16) // optically align with icon centre
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

