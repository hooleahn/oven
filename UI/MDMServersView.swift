import SwiftUI

// MARK: - MDM Servers store (simple, self-contained)

@MainActor
@Observable
final class MDMServerStore: ObservableObject {
    var servers: [MDMServer] = []
    private let metadataURL = AppSettings.defaultLocalStorageRoot
        .appendingPathComponent("mdm-servers.json")

    init() { load() }

    func add(_ server: MDMServer) {
        servers.append(server)
        save()
    }

    func update(id: UUID, _ apply: (inout MDMServer) -> Void) {
        guard let i = servers.firstIndex(where: { $0.id == id }) else { return }
        apply(&servers[i])
        save()
    }

    func delete(id: UUID) {
        if let server = servers.first(where: { $0.id == id }) {
            KeychainService.delete(key: server.keychainKey)
        }
        servers.removeAll { $0.id == id }
        save()
    }

    private func load() {
        servers = AppDatabase.shared.readOrDefault(.mdmServers, default: [])
    }

    private func save() {
        AppDatabase.shared.writeSilently(servers, to: .mdmServers)
    }
}

// MARK: - MDM Servers View

struct MDMServersView: View {
    @EnvironmentObject var serverStore: MDMServerStore
    @State private var selectedServer: MDMServer?
    @State private var isPresentingSheet = false
    @State private var editingServer: MDMServer?
    @State private var confirmDeleteServer: MDMServer? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if serverStore.servers.isEmpty {
                    EmptyStateView("No MDM Servers", systemImage: "server.rack",
                                   description: "Add a Jamf Pro server to use for MDM enrollment.") {
                        Button("Add Server") { isPresentingSheet = true }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    List(serverStore.servers, id: \.id, selection: $selectedServer) { server in
                        MDMServerRow(server: server).tag(server)
                    }
                    .listStyle(.inset)
                }
            }

            if let server = selectedServer {
                Divider()
                MDMServerDetailPane(
                    server: server,
                    onEdit: { editingServer = server },
                    onDelete: { confirmDeleteServer = server }
                )
                .frame(width: 280)
            }
        }
        .navigationTitle("MDM Servers")
        .confirmationDialog(
            confirmDeleteServer.map { "Delete \"\($0.friendlyName)\"?" } ?? "Delete server?",
            isPresented: Binding(get: { confirmDeleteServer != nil }, set: { if !$0 { confirmDeleteServer = nil } }),
            titleVisibility: .visible
        ) {
            if let server = confirmDeleteServer {
                Button("Delete Server", role: .destructive) {
                    serverStore.delete(id: server.id)
                    if selectedServer?.id == server.id { selectedServer = nil }
                    confirmDeleteServer = nil
                }
                Button("Cancel", role: .cancel) { confirmDeleteServer = nil }
            }
        } message: {
            Text("This MDM server and its stored credentials will be permanently removed.")
        }
        .sheet(isPresented: $isPresentingSheet) {
            MDMServerSheet(server: nil) { serverStore.add($0) }
        }
        .sheet(isPresented: Binding(
            get: { editingServer != nil },
            set: { if !$0 { editingServer = nil } }
        )) {
            if let toEdit = editingServer {
                MDMServerSheet(server: toEdit) { updated in
                    serverStore.update(id: toEdit.id) { existing in
                        existing.friendlyName = updated.friendlyName
                        existing.serverURL    = updated.serverURL
                        existing.serverAuthType = updated.serverAuthType
                        existing.serverUsername  = updated.serverUsername
                    }
                    editingServer = nil
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Spacer()
            Button { isPresentingSheet = true } label: {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }
}

// MARK: - Server row

struct MDMServerRow: View {
    let server: MDMServer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3).foregroundStyle(.blue).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.friendlyName).fontWeight(.medium)
                Text(server.serverURL.host ?? server.serverURL.absoluteString)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if server.serverPassword != nil {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.green)
                    .help("Password stored in Keychain")
            } else {
                Image(systemName: "lock.slash").font(.caption).foregroundStyle(.orange)
                    .help("No password configured")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail pane

struct MDMServerDetailPane: View {
    let server: MDMServer
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(.blue)
                Text(server.friendlyName).font(.headline).lineLimit(1)
                Text(server.serverURL.host ?? "").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(14).background(.bar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSection("Connection") {
                        DetailRow("URL", server.serverURL.absoluteString)
                        DetailRow("Authentication Type", server.serverAuthType)
                        DetailRow("API Client ID/Username", server.serverUsername)
                        DetailRow("API Client Secret/Password", server.serverPassword != nil ? "Stored in Keychain" : "Not set")
                    }
                    if let result = testResult {
                        DetailSection("Test result") {
                            Text(result)
                                .font(.callout)
                                .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 6) {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTesting {
                        HStack { ProgressView().controlSize(.small); Text("Testing…") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Test Connection", systemImage: "network").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).disabled(isTesting)

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
            }
            .padding(12)
        }
        .background(.windowBackground)
    }

    private func testConnection() async {
        guard let svc = server.makeJamfService() else {
            testResult = "✗ No password stored in Keychain"
            AppLogger.shared.error("No password stored in Keychain", source:"MDMServersView")
            return
        }
        isTesting = true
        do {
            let version = try await svc.testConnection()
            testResult = "✓ Connected — Jamf Pro \(version)"
            await AppLogger.shared.success("Connected to \(server.friendlyName)", source: "MDM Servers")
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
        isTesting = false
    }
}

// MARK: - Add/Edit sheet

struct MDMServerSheet: View {
    @Environment(\.dismiss) var dismiss
    let server: MDMServer?
    let onSave: (MDMServer) -> Void

    @State private var friendlyName = ""
    @State private var serverURL = ""
    @State private var serverAuthType = ""
    @State private var serverUsername = ""
    @State private var serverPassword = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(server == nil ? "Add MDM Server" : "Edit MDM Server").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(friendlyName.isEmpty || serverURL.isEmpty || serverUsername.isEmpty || serverPassword.isEmpty || serverAuthType.isEmpty)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Identity") {
                    LabeledContent("Friendly name") {
                        TextField("", text: $friendlyName, prompt: Text("e.g. Jamf Pro Production").foregroundColor(.secondary))
                    }
                }
                Section("Connection") {
                    LabeledContent("Server URL") {
                        TextField("", text: $serverURL, prompt: Text("https://yourorg.jamfcloud.com").foregroundColor(.secondary))
                    }
                    
                    Picker("Authentication Type", selection: $serverAuthType) {
                        Text("Username/Password (Basic)").tag("Basic")
                        Text("API Client/Secret").tag("API Client")
                    }.pickerStyle(.inline)
                    LabeledContent("API Client ID or Username") {
                        TextField("", text: $serverUsername, prompt: Text(" Username").foregroundColor(.secondary))
                    }
                    LabeledContent("API Client Secret or Password") {
                        SecureField("", text: $serverPassword, prompt: Text("Stored in Keychain").foregroundColor(.secondary))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 360)
        .onAppear {
            guard let s = server else { return }
            friendlyName = s.friendlyName
            serverURL = s.serverURL.absoluteString
            serverAuthType = s.serverAuthType
            serverUsername = s.serverUsername
            serverPassword = s.serverPassword ?? ""
        }
    }

    private func save() {
        let urlString = serverURL.hasPrefix("https") ? serverURL : "https://\(serverURL)"
        guard let url = URL(string: urlString) else { return }
        let s = MDMServer(
            id: server?.id ?? UUID(),
            friendlyName: friendlyName,
            serverURL: url,
            serverAuthType: serverAuthType,
            serverUsername: serverUsername
        )
        if !serverPassword.isEmpty { s.serverPassword = serverPassword }
        onSave(s)
        dismiss()
    }
}
