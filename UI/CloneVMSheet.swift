import SwiftUI


struct CloneVMSheet: View {
    let vm: VirtualMachine
    @Environment(VMStore.self) private var vmStore
    @Environment(BaseVMStore.self) private var baseVMStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var isCloning = false
    @State private var errorMessage: String?
    @State private var mdmWarningDismissed = false

    private var showMDMWarning: Bool {
        !mdmWarningDismissed && vm.mdmServerID != nil
    }

    private var sanitisedName: String {
        let base = displayName.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let suffix = String(UUID().uuidString.prefix(6).lowercased())
        return base.isEmpty ? "\(vm.name)-clone-\(suffix)" : "\(base)-\(suffix)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clone \"\(vm.displayName.isEmpty ? vm.name : vm.displayName)\"")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Clone") { Task { await cloneVM() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(isCloning)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section {
                    LabeledContent("Display name") {
                        TextField("", text: $displayName,
                                  prompt: Text("e.g. My Clone").foregroundStyle(.secondary))
                    }
                    LabeledContent("Tart name") {
                        Text(sanitisedName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("New VM") }
                  footer: { Text("A random suffix is appended to keep the tart name unique. The display name can be changed later.") }

                if showMDMWarning {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MDM Enrollment Warning")
                                    .font(.callout).fontWeight(.medium)
                                Text("This VM is enrolled in an MDM server. Cloning it may break or duplicate the MDM enrollment, causing issues with device management.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Dismiss") { mdmWarningDismissed = true }
                                .font(.caption).buttonStyle(.borderless)
                        }
                    }
                }

                if let err = errorMessage {
                    Section {
                        Label(err, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            if isCloning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cloning…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 260)
        .onAppear { displayName = vm.displayName.isEmpty ? vm.name : vm.displayName }
    }

    private func cloneVM() async {
        isCloning = true; errorMessage = nil
        do {
            try await vmStore.clone(
                source: vm.name,
                newName: sanitisedName,
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                description: vm.description,
                tags: vm.tags,
                macOSVersion: vm.macOSVersion,
                osName: vm.osName,
                osVersion: vm.osVersion,
                isBetaOS: vm.isBetaOS,
                betaLabel: vm.betaLabel,
                customOSMajorVersion: vm.customOSMajorVersion,
                customOSReleaseName: vm.customOSReleaseName,
                cpuCount: vm.cpuCount,
                memoryGB: vm.memoryGB,
                diskGB: vm.diskGB,
                sshUsername: vm.sshUsername,
                osMetadata: vm.osMetadata
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCloning = false
    }
}
