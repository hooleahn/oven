import SwiftUI

struct MDMEnrollmentView: View {
    @EnvironmentObject var serverStore: MDMServerStore
    @State private var profiles: [MDMProfile] = []
    @State private var selectedProfile: MDMProfile?
    @State private var isPresentingSheet = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var confirmDeleteProfile: MDMProfile? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No Enrollment Profiles", systemImage: "lock.shield")
                    } description: {
                        Text("Create an enrollment profile linked to an MDM Server.")
                    } actions: {
                        Button("New Profile") { isPresentingSheet = true }
                            .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                        if serverStore.servers.isEmpty {
                            Text("Add an MDM Server first.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    List(profiles, id: \.id, selection: $selectedProfile) { profile in
                        MDMProfileRow(profile: profile, servers: serverStore.servers).tag(profile)
                    }
                    .listStyle(.inset)
                }
            }
            if let profile = selectedProfile {
                Divider()
                MDMProfileDetailPane(
                    profile: profile,
                    server: serverStore.servers.first(where: { $0.id == profile.serverID }),
                    isTesting: isTesting,
                    testResult: testResult,
                    onTest: { Task { await testConnection(profile) } },
                    onDelete: { confirmDeleteProfile = profile }
                )
                .frame(width: 280)
            }
        }
        .navigationTitle("MDM Enrollment")
        .confirmationDialog(
            confirmDeleteProfile.map { "Delete \"\($0.name)\"?" } ?? "Delete profile?",
            isPresented: Binding(get: { confirmDeleteProfile != nil }, set: { if !$0 { confirmDeleteProfile = nil } }),
            titleVisibility: .visible
        ) {
            if let profile = confirmDeleteProfile {
                Button("Delete Profile", role: .destructive) { deleteProfile(profile) }
                Button("Cancel", role: .cancel) { confirmDeleteProfile = nil }
            }
        } message: {
            Text("This enrollment profile will be permanently removed.")
        }
        .sheet(isPresented: $isPresentingSheet) {
            MDMProfileSheet(servers: serverStore.servers) { profiles.append($0); saveProfiles() }
        }
        .onAppear { loadProfiles() }
    }

    private var toolbar: some View {
        HStack {
            Spacer()
            Button { isPresentingSheet = true } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .disabled(serverStore.servers.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    private func testConnection(_ profile: MDMProfile) async {
        guard let server = serverStore.servers.first(where: { $0.id == profile.serverID }),
              let svc = server.makeJamfService() else {
            testResult = "✗ Server not found or no credentials"
            AppLogger.shared.error("Failed to test connection: no server or credentials", source: "MDMProfileView")
            return
        }
        isTesting = true; testResult = nil
        do {
            let version = try await svc.testConnection()
            testResult = "✓ Connected — Jamf Pro \(version)"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
        isTesting = false
    }

    private func deleteProfile(_ profile: MDMProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedProfile?.id == profile.id { selectedProfile = nil }
        saveProfiles()
    }


    private func loadProfiles() {
        let loaded = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [MDMProfile]())
        guard !loaded.isEmpty else { return }
        profiles = loaded
    }

    private func saveProfiles() {
        AppDatabase.shared.writeSilently(profiles, to: .mdmProfiles)
    }
}

// MARK: - Profile row

struct MDMProfileRow: View {
    let profile: MDMProfile
    let servers: [MDMServer]

    var serverName: String {
        servers.first(where: { $0.id == profile.serverID })?.friendlyName ?? "Unknown server"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isActive ? "lock.shield.fill" : "lock.shield")
                .font(.title3).foregroundStyle(profile.isActive ? .blue : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).fontWeight(.medium)
                Text(serverName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if profile.isActive {
                Text("Active").font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail pane

struct MDMProfileDetailPane: View {
    let profile: MDMProfile
    let server: MDMServer?
    let isTesting: Bool
    let testResult: String?
    let onTest: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(.blue)
                Text(profile.name).font(.headline).lineLimit(1)
                Text(server?.friendlyName ?? "Unknown").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(14).background(.bar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSection("MDM Server") {
                        DetailRow("Name", server?.friendlyName ?? "—")
                        DetailRow("URL", server?.serverURL.host ?? "—")
                    }
                    DetailSection("Enrollment") {
                        DetailRow("Invitation ID", profile.invitationID.isEmpty ? "—" : profile.invitationID)
                        DetailRow("Type", profile.enrollmentType.rawValue)
                        DetailRow("Site", profile.site ?? "None")
                    }
                    if let result = testResult {
                        DetailSection("Test result") {
                            Text(result).font(.callout)
                                .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 6) {
                Button(action: onTest) {
                    if isTesting {
                        HStack { ProgressView().controlSize(.small); Text("Testing…") }.frame(maxWidth: .infinity)
                    } else {
                        Label("Test Connection", systemImage: "network").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent).disabled(isTesting)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
            }
            .padding(12)
        }
        .background(.windowBackground)
    }
}

// MARK: - New profile sheet

struct MDMProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    let servers: [MDMServer]
    let onSave: (MDMProfile) -> Void

    @State private var name = ""
    @State private var selectedServerID: UUID?
    @State private var invitationID = ""
    @State private var enrollmentType: MDMProfile.EnrollmentType = .profile
    @State private var site = ""
    @State private var tokenLifetime = 30
    @State private var autoRenew = true
    @State private var runPolicy = false
    @State private var policyName = ""

    var canSave: Bool {
        !name.isEmpty && selectedServerID != nil && !invitationID.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Enrollment Profile").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { save() }.buttonStyle(.borderedProminent).disabled(!canSave)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Profile") {
                    LabeledContent("Name") { TextField("", text: $name, prompt: Text("e.g. Jamf Dev Enrollment").foregroundColor(.secondary)) }
                }
                Section("MDM Server") {
                    Picker("Server", selection: $selectedServerID) {
                        Text("Select a server…").tag(Optional<UUID>.none)
                        ForEach(servers) { Text($0.friendlyName).tag(Optional($0.id)) }
                    }
                    if servers.isEmpty {
                        Label("Add an MDM Server first.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                Section("Enrollment") {
                    LabeledContent("Invitation ID") {
                        TextField("", text: $invitationID, prompt: Text("Paste Jamf enrollment invitation ID").foregroundColor(.secondary))
                    }
                    Picker("Enrollment type", selection: $enrollmentType) {
                        ForEach(MDMProfile.EnrollmentType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }
                Section("Scope") {
                    LabeledContent("Site") { TextField("", text: $site, prompt: Text("Optional").foregroundColor(.secondary)) }
                    LabeledContent("Token lifetime: \(tokenLifetime) days") {
                        Stepper("", value: $tokenLifetime, in: 1...365)
                    }
                    Toggle("Auto-renew token", isOn: $autoRenew)
                    Toggle("Run policy on enroll", isOn: $runPolicy)
                    if runPolicy {
                        LabeledContent("Policy name") { TextField("", text: $policyName, prompt: Text("e.g. Dev Bootstrap").foregroundColor(.secondary)) }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
        .onAppear {
            if selectedServerID == nil { selectedServerID = servers.first?.id }
        }
    }

    private func save() {
        guard let serverID = selectedServerID else { return }
        let p = MDMProfile(
            name: name, serverID: serverID,
            invitationID: invitationID,
            enrollmentType: enrollmentType,
            site: site.isEmpty ? nil : site,
            tokenLifetimeDays: tokenLifetime,
            autoRenewToken: autoRenew,
            runPolicyOnEnroll: runPolicy,
            enrollmentPolicyName: runPolicy && !policyName.isEmpty ? policyName : nil
        )
        onSave(p)
        dismiss()
    }
}
