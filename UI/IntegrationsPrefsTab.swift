import SwiftUI

struct IntegrationsPrefsTab: View {
    @State private var credentials: [RegistryCredential] = []
    @State private var isPresentingCredentialSheet = false
    @State private var editingCredential: RegistryCredential?

    private let credentialsURL = AppSettings.defaultLocalStorageRoot
        .appendingPathComponent("registry-credentials.json")

    var body: some View {
        Form {
            Section {
                if credentials.isEmpty {
                    Text("No registry credentials configured.").foregroundStyle(.secondary)
                } else {
                    ForEach(credentials) { cred in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cred.registry).fontWeight(.medium)
                                Text(cred.username).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: cred.password != nil ? "lock.fill" : "lock.slash")
                                .foregroundStyle(cred.password != nil ? .green : .orange)
                            Button("Edit")   { editingCredential = cred }
                                .buttonStyle(.bordered).controlSize(.mini)
                            Button("Delete") { deleteCredential(cred) }
                                .buttonStyle(.bordered).controlSize(.mini).tint(.red)
                        }
                    }
                }
                Button("Add Registry Credentials") { isPresentingCredentialSheet = true }
                    .buttonStyle(.bordered)
            } header: { Text("Registry credentials") }
              footer: { Text("Credentials are stored in Keychain and used with `tart login` before push/pull operations.") }
        }
        .formStyle(.grouped)
        .navigationTitle("Integrations")
        .onAppear { loadCredentials() }
        .sheet(isPresented: $isPresentingCredentialSheet, onDismiss: loadCredentials) {
            RegistryCredentialSheet(credential: nil, onSave: { save($0) })
        }
        .sheet(item: $editingCredential, onDismiss: loadCredentials) { cred in
            RegistryCredentialSheet(credential: cred, onSave: { save($0) })
        }
    }

    private func loadCredentials() {
        let loaded = AppDatabase.shared.readOrDefault(.registryCredentials, default: [RegistryCredential]())
        guard !loaded.isEmpty || true
        else { credentials = []; return }
        credentials = loaded
    }
    private func save(_ cred: RegistryCredential) {
        if let idx = credentials.firstIndex(where: { $0.id == cred.id }) {
            credentials[idx] = cred
        } else {
            credentials.append(cred)
        }
        AppDatabase.shared.writeSilently(credentials, to: .registryCredentials)
    }
    private func deleteCredential(_ cred: RegistryCredential) {
        credentials.removeAll { $0.id == cred.id }
        AppDatabase.shared.writeSilently(credentials, to: .registryCredentials)
    }
}


// MARK: - Registry Credential Sheet

struct RegistryCredentialSheet: View {
    @Environment(\.dismiss) var dismiss
    let credential: RegistryCredential?
    let onSave: (RegistryCredential) -> Void

    @State private var registry = "ghcr.io"
    @State private var customRegistry = ""
    @State private var useCustomRegistry = false
    @State private var username = ""
    @State private var password = ""

    private var effectiveRegistry: String {
        useCustomRegistry ? customRegistry : registry
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(credential == nil ? "Add Registry" : "Edit Registry").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") {
                    var cred = credential ?? RegistryCredential(id: UUID(), registry: effectiveRegistry, username: username)
                    cred.registry = effectiveRegistry; cred.username = username
                    if !password.isEmpty { cred.password = password }
                    onSave(cred); dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(effectiveRegistry.isEmpty || username.isEmpty)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Registry") {
                    LabeledContent("Host") {
                        Picker("", selection: $useCustomRegistry) {
                            Text("GitHub Container Registry (ghcr.io)").tag(false)
                                .help("ghcr.io")
                            Text("Docker Hub (docker.io)").tag(false)
                            Text("Other…").tag(true)
                        }
                        .labelsHidden()
                        .onChange(of: useCustomRegistry) { _, custom in
                            if !custom { registry = "ghcr.io" }
                        }
                    }
                    if useCustomRegistry {
                        LabeledContent("Custom host") {
                            TextField("", text: $customRegistry,
                                      prompt: Text("e.g. registry.example.com").foregroundColor(.secondary))
                        }
                    }
                }
                Section("Authentication") {
                    LabeledContent("Username / org") {
                        TextField("", text: $username,
                                  prompt: Text("e.g. myorg").foregroundColor(.secondary))
                    }
                    LabeledContent("Password / Token") {
                        SecureField("", text: $password,
                                    prompt: Text("GitHub PAT or Docker Hub token").foregroundColor(.secondary))
                    }
                }
                if credential != nil {
                    Section {
                        Text("Leave password blank to keep the existing token.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 280)
        .onAppear {
            if let c = credential {
                username = c.username
                let known = ["ghcr.io", "docker.io"]
                if known.contains(c.registry) {
                    registry = c.registry
                    useCustomRegistry = false
                } else {
                    customRegistry = c.registry
                    useCustomRegistry = true
                }
            }
        }
    }
}

// MARK: - URL helper

extension URL {
    var abbreviatingWithTilde: String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
