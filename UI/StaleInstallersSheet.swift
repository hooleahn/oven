import SwiftUI

// MARK: - StaleInstallersSheet

struct StaleInstallersSheet: View {
    let thresholdDays: Int

    @Environment(VMStore.self) private var vmStore
    @Environment(InstallerStore.self) private var installerStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID> = []
    @State private var fileSizes: [UUID: Int64] = [:]
    @State private var isDeleting = false

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -thresholdDays, to: Date()) ?? Date()
    }

    // MARK: - Derived last-used date per installer
    // Derived from base VM builtAt where manualBuildConfig.customInstallerID matches.

    private func lastUsedDate(for installer: Installer) -> Date? {
        vmStore.vms
            .filter { $0.isBaseVM && $0.manualBuildConfig?.customInstallerID == installer.id }
            .compactMap { $0.builtAt }
            .max()
    }

    // MARK: - Stale installer list

    private struct StaleInstaller: Identifiable {
        let installer: Installer
        let lastUsed: Date
        var id: UUID { installer.id }
    }

    private var staleInstallers: [StaleInstaller] {
        installerStore.installers.compactMap { inst in
            guard let date = lastUsedDate(for: inst), date < cutoff else { return nil }
            return StaleInstaller(installer: inst, lastUsed: date)
        }
        .sorted { $0.lastUsed < $1.lastUsed }
    }

    private var totalSelectedBytes: Int64 {
        selectedIDs.reduce(Int64(0)) { sum, id in
            sum + (fileSizes[id] ?? 0)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if staleInstallers.isEmpty {
                    ContentUnavailableView(
                        "No Stale Installers",
                        systemImage: "checkmark.seal",
                        description: Text("No custom installers with a build date older than \(thresholdDays) days were found.")
                    )
                } else {
                    List(selection: $selectedIDs) {
                        ForEach(staleInstallers) { item in
                            installerRow(item)
                                .tag(item.id)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Stale Installers (>\(thresholdDays) days)")
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
                            let bytes = totalSelectedBytes
                            let label = bytes > 0
                                ? String(format: "Delete Selected (%.1f GB)",
                                         Double(bytes) / 1_073_741_824)
                                : "Delete Selected"
                            Text(label)
                        }
                    }
                    .disabled(selectedIDs.isEmpty || isDeleting)
                    .tint(.red)
                }
            }
            .task { await computeFileSizes() }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    // MARK: - Row

    @ViewBuilder
    private func installerRow(_ item: StaleInstaller) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.installer.displayName)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    Label(RelativeDateTimeFormatter().localizedString(for: item.lastUsed, relativeTo: Date()),
                          systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)

                    if let bytes = fileSizes[item.id] {
                        Label(String(format: "%.1f GB", Double(bytes) / 1_073_741_824),
                              systemImage: "internaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("Unknown size", systemImage: "internaldrive")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                // Clarify what deletion does for unmanaged copies
                if !item.installer.isManagedCopy {
                    Text("Removes from library only — original file not deleted.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func deleteSelected() async {
        isDeleting = true
        for item in staleInstallers where selectedIDs.contains(item.id) {
            installerStore.delete(item.installer)
        }
        selectedIDs = []
        isDeleting = false
        if staleInstallers.isEmpty { dismiss() }
    }

    private func computeFileSizes() async {
        var result: [UUID: Int64] = [:]
        for item in staleInstallers {
            guard let path = item.installer.localPath else { continue }
            let size = await Task.detached(priority: .utility) {
                (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            }.value
            if size > 0 { result[item.id] = size }
        }
        fileSizes = result
    }
}
