import SwiftUI

// MARK: - Enrollment view

struct MDMEnrollmentView: View {
    @EnvironmentObject var serverStore: MDMServerStore
    @State private var profiles: [MDMProfile] = []
    @State private var selectedProfile: MDMProfile?
    @State private var isPresentingSheet = false
    @State private var editingProfile: MDMProfile? = nil
    @State private var confirmDeleteProfile: MDMProfile? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if profiles.isEmpty {
                    EmptyStateView("No Enrollment Profiles", systemImage: "lock.shield",
                                   description: "Create an enrollment profile to use for MDM enrollment.") {
                        Button("New Profile") { isPresentingSheet = true }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    profile: profileBinding(for: profile.id),
                    server: serverStore.servers.first(where: { $0.id == profile.serverID }),
                    servers: serverStore.servers,
                    onEdit: { editingProfile = profile },
                    onDelete: { confirmDeleteProfile = profile }
                )
                .frame(width: 280)
                .id(profile.id)
            }
        }
        .navigationTitle("MDM Enrollment")
        .confirmationDialog(
            confirmDeleteProfile.map { "Delete \"\($0.displayName)\"?" } ?? "Delete profile?",
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
        .sheet(item: $editingProfile) { profile in
            MDMProfileSheet(servers: serverStore.servers, editing: profile) { updated in
                if let i = profiles.firstIndex(where: { $0.id == updated.id }) {
                    profiles[i] = updated
                    // Keep selected profile in sync
                    if selectedProfile?.id == updated.id { selectedProfile = updated }
                    saveProfiles()
                }
            }
        }
        .onAppear { loadProfiles() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button { isPresentingSheet = true } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    private func profileBinding(for id: UUID) -> Binding<MDMProfile> {
        Binding(
            get: { profiles.first(where: { $0.id == id }) ?? MDMProfile(displayName: "") },
            set: { updated in
                if let i = profiles.firstIndex(where: { $0.id == id }) {
                    profiles[i] = updated
                    saveProfiles()
                }
            }
        )
    }

    private func deleteProfile(_ profile: MDMProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedProfile?.id == profile.id { selectedProfile = nil }
        confirmDeleteProfile = nil
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

    private var serverName: String {
        if let sid = profile.serverID {
            return servers.first(where: { $0.id == sid })?.friendlyName ?? "Unknown Server"
        }
        return profile.customServerURL.isEmpty ? "Custom" : profile.customServerURL
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.title3)
                .foregroundStyle(profile.isValid ? .green : .red)
                .frame(width: 28)
                .help(profile.isValid ? "Invitation is valid" : "Invitation has expired")
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).fontWeight(.medium)
                Text(serverName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let exp = profile.expirationDate {
                Text(exp, style: .date)
                    .font(.caption)
                    .foregroundStyle(profile.isValid ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail pane

struct MDMProfileDetailPane: View {
    @Binding var profile: MDMProfile
    let server: MDMServer?
    let servers: [MDMServer]
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isFetchingExpiry = false
    @State private var fetchError: String? = nil

    private var serverLabel: String {
        if let s = server { return s.friendlyName }
        return profile.customServerURL.isEmpty ? "Custom" : profile.customServerURL
    }

    private var canFetchExpiry: Bool {
        guard let s = server else { return false }
        guard s.featureCheckInvitationStatus else { return false }
        let hasPrivilege = s.storedPrivileges.isEmpty || s.storedPrivileges.contains("Read Computer Enrollment Invitations")
        return !profile.invitationID.isEmpty && hasPrivilege
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: profile.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(profile.isValid ? .green : .red)
                Text(profile.displayName).font(.headline).lineLimit(1)
                Text(serverLabel).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(14).background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailSection("Identity") {
                        DetailRow("Display Name", profile.displayName)
                        if !profile.profileDescription.isEmpty {
                            DetailRow("Description", profile.profileDescription)
                        }
                    }

                    DetailSection("MDM Server") {
                        if let s = server {
                            DetailRow("Server", s.friendlyName)
                            DetailRow("URL", s.serverURL.host ?? s.serverURL.absoluteString)
                        } else {
                            DetailRow("Server", "Custom")
                            if !profile.customServerURL.isEmpty {
                                DetailRow("URL", profile.customServerURL)
                            }
                        }
                    }

                    DetailSection("Enrollment") {
                        DetailRow("Invitation ID", profile.invitationID.isEmpty ? "—" : profile.invitationID)
                        if let exp = profile.expirationDate {
                            DetailRow("Expires", exp.formatted(date: .abbreviated, time: .omitted))
                            if !profile.isValid {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.red)
                                    Text("This invitation has expired.")
                                        .font(.caption).foregroundStyle(.red)
                                }
                                .padding(.horizontal, 14).padding(.bottom, 8)
                            }
                        } else {
                            DetailRow("Expires", "Unknown")
                        }
                    }

                    if let err = fetchError {
                        DetailSection("Fetch Error") {
                            Text(err)
                                .font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                }
            }

            Divider()
            VStack(spacing: 6) {
                if canFetchExpiry {
                    Button {
                        Task { await fetchExpiry() }
                    } label: {
                        if isFetchingExpiry {
                            HStack { ProgressView().controlSize(.small); Text("Fetching…") }
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Fetch Expiration Date", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFetchingExpiry)
                } else if server != nil {
                    Label("Missing 'Read Computer Enrollment Invitations' privilege", systemImage: "lock.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

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

    private func fetchExpiry() async {
        guard let s = server, let svc = s.makeJamfService() else { return }
        isFetchingExpiry = true
        fetchError = nil
        do {
            let date = try await svc.fetchInvitationExpiry(invitationID: profile.invitationID)
            profile.expirationDate = date
            if date == nil {
                fetchError = "No expiration date found for this invitation ID."
            }
        } catch {
            fetchError = error.localizedDescription
        }
        isFetchingExpiry = false
    }
}

// MARK: - New / Edit profile sheet

struct MDMProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    let servers: [MDMServer]
    /// Non-nil when editing an existing profile.
    var editing: MDMProfile? = nil
    let onSave: (MDMProfile) -> Void

    @State private var displayName = ""
    @State private var description = ""
    /// nil = Custom mode
    @State private var selectedServerID: UUID?
    @State private var customServerURL = ""
    @State private var invitationID = ""
    @State private var expirationDate: Date? = nil
    @State private var hasExpiration = false

    private var isEditing: Bool { editing != nil }
    private var useCustomServer: Bool { selectedServerID == nil }

    private var canSave: Bool {
        !displayName.isEmpty && !invitationID.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Enrollment Profile" : "New Enrollment Profile").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button(isEditing ? "Save Changes" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Identity") {
                    LabeledContent("Display Name") {
                        TextField("", text: $displayName, prompt: Text("e.g. Dev Enrollment").foregroundColor(.secondary))
                    }
                    LabeledContent("Description") {
                        TextField("", text: $description, prompt: Text("Optional").foregroundColor(.secondary))
                    }
                }

                Section("MDM Server") {
                    Picker("Server", selection: $selectedServerID) {
                        Text("Custom").tag(Optional<UUID>.none)
                        ForEach(servers) { Text($0.friendlyName).tag(Optional($0.id)) }
                    }
                    if useCustomServer {
                        LabeledContent("Server URL") {
                            TextField("", text: $customServerURL, prompt: Text("https://yourorg.jamfcloud.com").foregroundColor(.secondary))
                        }
                    }
                }

                Section("Enrollment") {
                    LabeledContent("Invitation ID") {
                        TextField("", text: $invitationID, prompt: Text("Paste enrollment invitation ID").foregroundColor(.secondary))
                    }
                    Toggle("Set expiration date manually", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expiration Date", selection: Binding(
                            get: { expirationDate ?? Date() },
                            set: { expirationDate = $0 }
                        ), displayedComponents: .date)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 360)
        .onAppear { populate() }
    }

    private func populate() {
        if let p = editing {
            displayName = p.displayName
            description = p.profileDescription
            selectedServerID = p.serverID
            customServerURL = p.customServerURL
            invitationID = p.invitationID
            hasExpiration = p.expirationDate != nil
            expirationDate = p.expirationDate
        } else {
            // Default to first linked server when creating
            if !servers.isEmpty {
                selectedServerID = servers.first?.id
            }
        }
    }

    private func save() {
        let p = MDMProfile(
            id: editing?.id ?? UUID(),
            displayName: displayName,
            profileDescription: description,
            serverID: selectedServerID,
            customServerURL: useCustomServer ? customServerURL : "",
            invitationID: invitationID,
            expirationDate: hasExpiration ? expirationDate : nil
        )
        onSave(p)
        dismiss()
    }
}
