import SwiftUI


struct CloneVMSheet: View {
    let vm: VirtualMachine
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var isCloning = false
    @State private var errorMessage: String?

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
                                  prompt: Text("e.g. My Clone").foregroundColor(.secondary))
                    }
                    LabeledContent("Tart name") {
                        Text(sanitisedName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("New VM") }
                  footer: { Text("A random suffix is appended to keep the tart name unique. The display name can be changed later.") }

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
                cpuCount: vm.cpuCount,
                memoryGB: vm.memoryGB,
                diskGB: vm.diskGB,
                sshUsername: vm.sshUsername
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCloning = false
    }
}
