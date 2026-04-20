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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    serverID: server.id,
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
                        existing.friendlyName   = updated.friendlyName
                        existing.serverURL      = updated.serverURL
                        existing.serverAuthType = updated.serverAuthType
                        existing.serverUsername = updated.serverUsername
                        existing.featureCheckEnrollment       = updated.featureCheckEnrollment
                        existing.featureDeleteFromJamf        = updated.featureDeleteFromJamf
                        existing.featureCheckInvitationStatus = updated.featureCheckInvitationStatus
                    }
                    editingServer = nil
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
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
            connectionIcon
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

    @ViewBuilder
    private var connectionIcon: some View {
        switch server.connectionState {
        case .connected:
            let hasMissingPrivileges = !server.storedPrivileges.isEmpty &&
                MDMServerDetailPane.activeRequiredPrivileges(for: server).contains { !server.storedPrivileges.contains($0.name) }
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(hasMissingPrivileges ? .yellow : .green)
                .font(.title3)
                .frame(width: 28)
                .help(hasMissingPrivileges ? "Connected — missing required privileges" : "Connection verified")
        case .failed:
            Image(systemName: "xmark.seal.fill")
                .foregroundStyle(.red)
                .font(.title3)
                .frame(width: 28)
                .help("Connection failed")
        case .testing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28)
        case .unknown:
            Image(systemName: "server.rack")
                .font(.title3).foregroundStyle(.blue).frame(width: 28)
        }
    }
}

// MARK: - Detail pane

struct MDMServerDetailPane: View {
    let serverID: UUID
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isTesting = false
    @EnvironmentObject var serverStore: MDMServerStore

    struct RequiredPrivilege {
        let name: String
        let reason: String
        /// Returns true when the feature that needs this privilege is enabled on the given server.
        let isActive: (MDMServer) -> Bool
    }

    static let requiredPrivileges: [RequiredPrivilege] = [
        RequiredPrivilege(name: "Read Computers",
                          reason: "Required to check if a VM is enrolled in Jamf Pro.",
                          isActive: { $0.featureCheckEnrollment }),
        RequiredPrivilege(name: "Delete Computers",
                          reason: "Required to remove a VM from Jamf Pro when deleted from Oven.",
                          isActive: { $0.featureDeleteFromJamf }),
        RequiredPrivilege(name: "Read Computer Enrollment Invitations",
                          reason: "Required to fetch the expiration date of enrollment invitations.",
                          isActive: { $0.featureCheckInvitationStatus }),
    ]

    /// Privileges whose associated feature is currently enabled for the given server.
    static func activeRequiredPrivileges(for server: MDMServer) -> [RequiredPrivilege] {
        requiredPrivileges.filter { $0.isActive(server) }
    }

    /// Always reads the current value from the store so updates are instant.
    private var server: MDMServer? {
        serverStore.servers.first { $0.id == serverID }
    }

    var body: some View {
        Group {
            if let server {
                content(for: server)
            }
        }
        .background(.windowBackground)
    }

    @ViewBuilder
    private func content(for server: MDMServer) -> some View {
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
                        DetailRow(server.serverAuthType == "API Client" ? "Client ID" : "Username", server.serverUsername)
                        DetailRow(server.serverAuthType == "API Client" ? "API Client Secret" : "Password", server.serverPassword != nil ? "Stored in Keychain" : "Not set")
                        DetailRow("Features", featuresLabel(for: server))
                    }
                    if let result = server.lastTestResult {
                        DetailSection("Last Test") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result)
                                    .font(.callout)
                                    .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                                if let date = server.lastTestedAt {
                                    Text("Tested \(date.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    if !server.storedPrivileges.isEmpty {
                        let missingPrivileges = MDMServerDetailPane.activeRequiredPrivileges(for: server).filter {
                            !server.storedPrivileges.contains($0.name)
                        }
                        if !missingPrivileges.isEmpty {
                            DetailSection("Missing Privileges") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(missingPrivileges, id: \.name) { priv in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                                .padding(.top, 1)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(priv.name)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                Text(priv.reason)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            }
                        }
                        DetailSection("Privileges") {
                            PrivilegesListView(privileges: server.storedPrivileges)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 6) {
                Button {
                    Task { await testConnection(server: server) }
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
    }

    private func featuresLabel(for server: MDMServer) -> String {
        let labels: [(Bool, String)] = [
            (server.featureCheckEnrollment,       "Enrollment Check"),
            (server.featureDeleteFromJamf,        "Delete from Jamf"),
            (server.featureCheckInvitationStatus, "Invitation Status"),
        ]
        let enabled = labels.filter(\.0).map(\.1)
        return enabled.isEmpty ? "None enabled" : enabled.joined(separator: ", ")
    }

    private func testConnection(server: MDMServer) async {
        guard let svc = server.makeJamfService() else {
            let msg = "✗ No password stored in Keychain"
            AppLogger.shared.error("No password stored in Keychain", source: "MDMServersView")
            serverStore.update(id: serverID) {
                $0.connectionState = .failed("No password stored in Keychain")
                $0.lastTestResult = msg
                $0.lastTestedAt = Date()
            }
            return
        }
        isTesting = true
        serverStore.update(id: serverID) { $0.connectionState = .testing }
        do {
            let version = try await svc.testConnection()
            let privileges = (try? await svc.fetchPrivileges()) ?? []
            let privSummary = privileges.isEmpty ? "no privileges returned" : "\(privileges.count) privilege\(privileges.count == 1 ? "" : "s")"
            let result = "✓ Connected — Jamf Pro \(version) · \(privSummary)"
            await AppLogger.shared.success("Connected to \(server.friendlyName)", source: "MDM Servers")
            serverStore.update(id: serverID) {
                $0.connectionState = .connected
                $0.storedPrivileges = privileges.sorted()
                $0.lastTestResult = result
                $0.lastTestedAt = Date()
            }
        } catch {
            let msg = "✗ \(error.localizedDescription)"
            serverStore.update(id: serverID) {
                $0.connectionState = .failed(error.localizedDescription)
                $0.lastTestResult = msg
                $0.lastTestedAt = Date()
            }
        }
        isTesting = false
    }
}

// MARK: - Privileges list

private struct PrivilegesListView: View {
    let privileges: [String]
    @State private var isExpanded = false

    private let previewCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let shown = isExpanded ? privileges : Array(privileges.prefix(previewCount))
            ForEach(shown, id: \.self) { priv in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(priv)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            if privileges.count > previewCount {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Show less" : "Show \(privileges.count - previewCount) more…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
    @State private var featureCheckEnrollment = true
    @State private var featureDeleteFromJamf = true
    @State private var featureCheckInvitationStatus = true

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
                        TextField("", text: $serverUsername, prompt: Text(" Client ID/Username").foregroundColor(.secondary))
                    }
                    LabeledContent("API Client Secret or Password") {
                        SecureField("", text: $serverPassword, prompt: Text("Stored in Keychain").foregroundColor(.secondary))
                    }
                }
                Section("Features") {
                    Toggle("Check Computer Enrollment", isOn: $featureCheckEnrollment)
                    Toggle("Delete Computer from Jamf", isOn: $featureDeleteFromJamf)
                    Toggle("Check Enrollment Invitation Status", isOn: $featureCheckInvitationStatus)
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
            featureCheckEnrollment      = s.featureCheckEnrollment
            featureDeleteFromJamf       = s.featureDeleteFromJamf
            featureCheckInvitationStatus = s.featureCheckInvitationStatus
        }
    }

    private func save() {
        let urlString = serverURL.hasPrefix("https") ? serverURL : "https://\(serverURL)"
        guard let url = URL(string: urlString) else { return }
        var s = MDMServer(
            id: server?.id ?? UUID(),
            friendlyName: friendlyName,
            serverURL: url,
            serverAuthType: serverAuthType,
            serverUsername: serverUsername
        )
        s.featureCheckEnrollment      = featureCheckEnrollment
        s.featureDeleteFromJamf       = featureDeleteFromJamf
        s.featureCheckInvitationStatus = featureCheckInvitationStatus
        if !serverPassword.isEmpty { s.serverPassword = serverPassword }
        onSave(s)
        dismiss()
    }
}
