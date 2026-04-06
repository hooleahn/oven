import SwiftUI


struct PushToRegistrySheet: View {
    let vmName: String
    /// Called with (imageRef, credentials) when user confirms
    let onPush: (String, [RegistryCredential]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var credentials: [RegistryCredential] = []
    @State private var selectedCredential: RegistryCredential? = nil
    @State private var imageName: String = ""
    @State private var imageTag: String = "latest"

    private var imageRef: String {
        guard let cred = selectedCredential else { return "" }
        let name = imageName.trimmingCharacters(in: .whitespaces)
        let tag  = imageTag.trimmingCharacters(in: .whitespaces).isEmpty ? "latest" : imageTag.trimmingCharacters(in: .whitespaces)
        return "\(cred.registry)/\(cred.username)/\(name):\(tag)"
    }

    private var canPush: Bool {
        selectedCredential != nil && !imageName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Push \"\(vmName)\" to Registry").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Push") { onPush(imageRef, credentials) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!canPush)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Registry") {
                    if credentials.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text("No registry credentials configured. Add them in Preferences → Integrations.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Account", selection: $selectedCredential) {
                            Text("Select…").tag(Optional<RegistryCredential>(nil))
                            ForEach(credentials) { cred in
                                Text("\(cred.registry) / \(cred.username)").tag(Optional(cred))
                            }
                        }
                    }
                }
                Section("Image") {
                    LabeledContent("Name") {
                        TextField("", text: $imageName,
                                  prompt: Text("e.g. my-macos-vm").foregroundColor(.secondary))
                    }
                    LabeledContent("Tag") {
                        TextField("", text: $imageTag,
                                  prompt: Text("latest").foregroundColor(.secondary))
                    }
                    if !imageRef.isEmpty {
                        LabeledContent("Full ref") {
                            Text(imageRef)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320)
        .onAppear { loadCredentials() }
    }

    private func loadCredentials() {
        let loaded = AppDatabase.shared.readOrDefault(.registryCredentials, default: [RegistryCredential]())
        guard !loaded.isEmpty || true
        else { return }
        credentials = loaded
        selectedCredential = loaded.first
        imageName = vmName
    }
}
