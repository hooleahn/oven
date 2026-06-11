import SwiftUI

// MARK: - StaleVMsSheet

struct StaleVMsSheet: View {
    let thresholdDays: Int

    @Environment(VMStore.self) private var vmStore
    @Environment(MDMServerStore.self) private var serverStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID> = []
    @State private var removeFromMDM: Set<UUID> = []
    @State private var isDeleting = false
    @State private var sizeByID: [UUID: Int64] = [:]

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -thresholdDays, to: Date()) ?? Date()
    }

    // MARK: - Stale VM computation

    private var staleWorkingVMs: [VirtualMachine] {
        vmStore.vms.filter { vm in
            !vm.effectivelyBase
            && vm.status != .building
            && (vm.lastStartedAt.map { $0 < cutoff } ?? false)
        }
        .sorted { ($0.lastStartedAt ?? .distantPast) < ($1.lastStartedAt ?? .distantPast) }
    }

    private var staleBaseVMs: [VirtualMachine] {
        vmStore.vms.filter { vm in
            vm.isBaseVM && !vm.isOCIBased
            && vm.buildStatus == .ready
            && (vm.lastClonedAt.map { $0 < cutoff } ?? false)
        }
        .sorted { ($0.lastClonedAt ?? .distantPast) < ($1.lastClonedAt ?? .distantPast) }
    }

    private var staleRegistryVMs: [VirtualMachine] {
        vmStore.vms.filter { vm in
            vm.isOCIBased
            && (vm.lastClonedAt.map { $0 < cutoff } ?? false)
        }
        .sorted { ($0.lastClonedAt ?? .distantPast) < ($1.lastClonedAt ?? .distantPast) }
    }

    private var allStale: [VirtualMachine] {
        staleWorkingVMs + staleBaseVMs + staleRegistryVMs
    }

    private var totalSelectedGB: Double {
        selectedIDs.reduce(0.0) { sum, id in
            guard let vm = allStale.first(where: { $0.id == id }) else { return sum }
            if let gb = vm.actualDiskGB { return sum + Double(gb) }
            if let bytes = sizeByID[id] { return sum + Double(bytes) / 1_073_741_824 }
            return sum
        }
    }

    // MARK: - MDM eligibility

    private func jamfServer(for vm: VirtualMachine) -> MDMServer? {
        guard let serverID = vm.mdmServerID,
              let server = serverStore.servers.first(where: { $0.id == serverID }),
              server.featureDeleteFromJamf,
              !vm.serialNumber.isEmpty else { return nil }
        return server
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if allStale.isEmpty {
                    ContentUnavailableView(
                        "No Stale VMs",
                        systemImage: "checkmark.seal",
                        description: Text("No VMs with a recorded last-use date older than \(thresholdDays) days were found.")
                    )
                } else {
                    List(selection: $selectedIDs) {
                        vmSection("Virtual Machines", vms: staleWorkingVMs, lastUsedKeyPath: \.lastStartedAt)
                        vmSection("Base VMs", vms: staleBaseVMs, lastUsedKeyPath: \.lastClonedAt)
                        vmSection("Registry VMs", vms: staleRegistryVMs, lastUsedKeyPath: \.lastClonedAt)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Stale VMs (>\(thresholdDays) days)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        Task { await deleteSelected() }
                    } label: {
                        if isDeleting {
                            ProgressView().controlSize(.small)
                        } else {
                            let gb = totalSelectedGB
                            let label = gb > 0
                                ? String(format: "Delete Selected (%.1f GB)", gb)
                                : "Delete Selected"
                            Text(label)
                        }
                    }
                    .disabled(selectedIDs.isEmpty || isDeleting)
                    .tint(.red)
                }
            }
            .task { await computeSizes() }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    // MARK: - Section builder

    @ViewBuilder
    private func vmSection(_ title: String, vms: [VirtualMachine],
                           lastUsedKeyPath: KeyPath<VirtualMachine, Date?>) -> some View {
        if !vms.isEmpty {
            Section(title) {
                ForEach(vms) { vm in
                    staleVMRow(vm, lastUsed: vm[keyPath: lastUsedKeyPath])
                }
            }
        }
    }

    @ViewBuilder
    private func staleVMRow(_ vm: VirtualMachine, lastUsed: Date?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.displayName.isEmpty ? vm.name : vm.displayName)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    if let date = lastUsed {
                        Label(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()),
                              systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    sizeLabel(for: vm)
                }

                // MDM toggle for eligible working VMs
                if !vm.effectivelyBase, let _ = jamfServer(for: vm) {
                    Toggle(isOn: Binding(
                        get: { removeFromMDM.contains(vm.id) },
                        set: { on in
                            if on { removeFromMDM.insert(vm.id) }
                            else  { removeFromMDM.remove(vm.id) }
                        }
                    )) {
                        Text("Also remove from MDM")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(!selectedIDs.contains(vm.id))
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .tag(vm.id)
    }

    @ViewBuilder
    private func sizeLabel(for vm: VirtualMachine) -> some View {
        if let gb = vm.actualDiskGB {
            Label(String(format: "%.0f GB", Double(gb)), systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary)
        } else if let bytes = sizeByID[vm.id] {
            Label(String(format: "%.1f GB", Double(bytes) / 1_073_741_824), systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Label("Unknown size", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func deleteSelected() async {
        isDeleting = true
        for vm in allStale where selectedIDs.contains(vm.id) {
            let mdmServer = removeFromMDM.contains(vm.id) ? jamfServer(for: vm) : nil
            try? await vmStore.delete(vm: vm, mdmServer: mdmServer)
        }
        selectedIDs = []
        removeFromMDM = []
        isDeleting = false
        if allStale.isEmpty { dismiss() }
    }

    // Compute sizes from tart's TART_HOME for VMs missing actualDiskGB
    private func computeSizes() async {
        let tartHome = AppSettings.load().resolvedTartHome
        let vmsDir = tartHome.appendingPathComponent("vms")
        var result: [UUID: Int64] = [:]
        for vm in allStale where vm.actualDiskGB == nil {
            let vmDir = vmsDir.appendingPathComponent(vm.name)
            let size = await directorySize(vmDir)
            if size > 0 { result[vm.id] = size }
        }
        sizeByID = result
    }

    private func directorySize(_ url: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
            var total: Int64 = 0
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                          vals.isRegularFile == true,
                          let size = vals.fileSize else { continue }
                    total += Int64(size)
                }
            }
            return total
        }.value
    }
}
