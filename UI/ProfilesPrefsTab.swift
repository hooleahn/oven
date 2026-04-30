import SwiftUI

// MARK: - ProfilesPrefsTab

struct ProfilesPrefsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    @State private var editingProfileID: UUID?
    @State private var showAddSheet = false
    @State private var confirmDeleteID: UUID?

    var body: some View {
        Form {
            Section {
                ForEach(profileStore.profiles) { profile in
                    profileRow(profile)
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Each profile has its own VM metadata and TART_HOME. Switching profiles reloads the VM list from the selected profile's storage. VM disk images, IPSWs, and tool binaries are not affected.")
            }

            Section {
                Button("Add Profile…") { showAddSheet = true }
                    .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Profiles")
        .sheet(isPresented: $showAddSheet) {
            AddProfileSheet { name, tartHome, ipsw, templates in
                let p = profileStore.addProfile(name: name, tartHome: tartHome.isEmpty ? nil : tartHome)
                if !ipsw.isEmpty      { profileStore.setIPSWRoot(id: p.id, to: URL(fileURLWithPath: ipsw)) }
                if !templates.isEmpty { profileStore.setPackerTemplatesRoot(id: p.id, to: URL(fileURLWithPath: templates)) }
            }
        }
        .sheet(item: Binding(
            get: { editingProfileID.flatMap { id in profileStore.profiles.first { $0.id == id } } },
            set: { editingProfileID = $0?.id }
        )) { profile in
            EditProfileSheet(profile: profile) { name, tartHome, ipsw, templates in
                profileStore.rename(id: profile.id, to: name)
                profileStore.setTartHome(id: profile.id, to: tartHome.isEmpty ? nil : tartHome)
                profileStore.setIPSWRoot(id: profile.id, to: ipsw.isEmpty ? nil : URL(fileURLWithPath: ipsw))
                profileStore.setPackerTemplatesRoot(id: profile.id, to: templates.isEmpty ? nil : URL(fileURLWithPath: templates))
            }
        }
        .confirmationDialog(
            confirmDeleteID.flatMap { id in profileStore.profiles.first { $0.id == id } }
                .map { "Delete \"\($0.name)\"?" } ?? "Delete Profile?",
            isPresented: Binding(
                get: { confirmDeleteID != nil },
                set: { if !$0 { confirmDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = confirmDeleteID {
                Button("Delete Profile", role: .destructive) {
                    profileStore.deleteProfile(id: id)
                    confirmDeleteID = nil
                }
                Button("Cancel", role: .cancel) { confirmDeleteID = nil }
            }
        } message: {
            Text("The profile's metadata directory will be preserved on disk. VM disk images are not affected.")
        }
    }

    // MARK: - Profile row

    @ViewBuilder
    private func profileRow(_ profile: OvenProfile) -> some View {
        let isActive = profile.id == profileStore.activeProfileID

        HStack(spacing: 12) {
            // Active indicator
            Circle()
                .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(profileSummary(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !isActive {
                Button("Switch") {
                    profileStore.switchToProfile(id: profile.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Menu {
                Button("Edit…") { editingProfileID = profile.id }
                Divider()
                Button("Delete…", role: .destructive) {
                    confirmDeleteID = profile.id
                }
                .disabled(profileStore.profiles.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Profile options")
        }
        .padding(.vertical, 2)
    }

    private func profileSummary(_ profile: OvenProfile) -> String {
        var parts: [String] = []
        parts.append("VMs: " + (profile.tartHome.map { abbreviatingWithTilde($0) } ?? "~/.tart"))
        if let ipsw = profile.ipswStorageRoot {
            parts.append("IPSWs: " + abbreviatingWithTilde(ipsw.path))
        }
        if let tmpl = profile.packerTemplatesRoot {
            parts.append("Templates: " + abbreviatingWithTilde(tmpl.path))
        }
        return parts.joined(separator: " · ")
    }

    private func abbreviatingWithTilde(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Add Profile Sheet

private struct AddProfileSheet: View {
    let onAdd: (_ name: String, _ tartHome: String, _ ipsw: String, _ templates: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var tartHome = ""
    @State private var ipswPath = ""
    @State private var templatesPath = ""
    @State private var activePicker: PickerField?
    @State private var committedPicker: PickerField?

    enum PickerField { case tartHome, ipsw, templates }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                } header: { Text("Profile Name") }

                Section {
                    pathRow("TART_HOME", path: $tartHome,
                            placeholder: "Default (~/.tart)",
                            picker: .tartHome)
                } header: { Text("VM Storage") } footer: {
                    Text("Where tart stores VM disk images. Leave blank for the default (~/.tart).")
                }

                Section {
                    pathRow("IPSW Storage", path: $ipswPath,
                            placeholder: "Default",
                            picker: .ipsw)
                    pathRow("Packer Templates", path: $templatesPath,
                            placeholder: "Default",
                            picker: .templates)
                } header: { Text("Additional Storage") } footer: {
                    Text("Leave blank to use the platform defaults. Useful when the full workflow lives on an external drive.")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.escape)
                Button("Add Profile") {
                    onAdd(name, tartHome, ipswPath, templatesPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 460)
        .fileImporter(
            isPresented: Binding(get: { activePicker != nil }, set: { if !$0 { activePicker = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            defer { activePicker = nil; committedPicker = nil }
            guard let url = try? result.get() else { return }
            switch committedPicker {
            case .tartHome:  tartHome      = url.path
            case .ipsw:      ipswPath      = url.path
            case .templates: templatesPath = url.path
            case nil: break
            }
        }
    }

    @ViewBuilder
    private func pathRow(_ label: String, path: Binding<String>, placeholder: String, picker: PickerField) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                pathIcon(path.wrappedValue)
                TextField(placeholder, text: path)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { committedPicker = picker; activePicker = picker }.controlSize(.small)
                if !path.wrappedValue.isEmpty {
                    Button("Reset") { path.wrappedValue = "" }.controlSize(.small).tint(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func pathIcon(_ path: String) -> some View {
        if path.isEmpty {
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        } else {
            let exists = FileManager.default.fileExists(atPath: path)
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(exists ? .green : .red)
        }
    }
}

// MARK: - Edit Profile Sheet

private struct EditProfileSheet: View {
    let profile: OvenProfile
    let onSave: (_ name: String, _ tartHome: String, _ ipsw: String, _ templates: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var tartHome: String
    @State private var ipswPath: String
    @State private var templatesPath: String
    @State private var activePicker: AddProfileSheet.PickerField?
    @State private var committedPicker: AddProfileSheet.PickerField?

    init(profile: OvenProfile, onSave: @escaping (_ name: String, _ tartHome: String, _ ipsw: String, _ templates: String) -> Void) {
        self.profile = profile
        self.onSave  = onSave
        _name          = State(initialValue: profile.name)
        _tartHome      = State(initialValue: profile.tartHome ?? "")
        _ipswPath      = State(initialValue: profile.ipswStorageRoot?.path ?? "")
        _templatesPath = State(initialValue: profile.packerTemplatesRoot?.path ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                } header: { Text("Profile Name") }

                Section {
                    pathRow("TART_HOME", path: $tartHome,
                            placeholder: "Default (~/.tart)",
                            picker: .tartHome)
                } header: { Text("VM Storage") } footer: {
                    Text("Where tart stores VM disk images. Leave blank for the default (~/.tart).")
                }

                Section {
                    pathRow("IPSW Storage", path: $ipswPath,
                            placeholder: "Default",
                            picker: .ipsw)
                    pathRow("Packer Templates", path: $templatesPath,
                            placeholder: "Default",
                            picker: .templates)
                } header: { Text("Additional Storage") } footer: {
                    Text("Leave blank to use the platform defaults.")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.escape)
                Button("Save") {
                    onSave(name, tartHome, ipswPath, templatesPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 460)
        .fileImporter(
            isPresented: Binding(get: { activePicker != nil }, set: { if !$0 { activePicker = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            defer { activePicker = nil; committedPicker = nil }
            guard let url = try? result.get() else { return }
            switch committedPicker {
            case .tartHome:  tartHome      = url.path
            case .ipsw:      ipswPath      = url.path
            case .templates: templatesPath = url.path
            case nil: break
            }
        }
    }

    @ViewBuilder
    private func pathRow(_ label: String, path: Binding<String>, placeholder: String, picker: AddProfileSheet.PickerField) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                pathIcon(path.wrappedValue)
                TextField(placeholder, text: path).textFieldStyle(.roundedBorder)
                Button("Choose…") { committedPicker = picker; activePicker = picker }.controlSize(.small)
                if !path.wrappedValue.isEmpty {
                    Button("Reset") { path.wrappedValue = "" }.controlSize(.small).tint(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func pathIcon(_ path: String) -> some View {
        if path.isEmpty {
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        } else {
            let exists = FileManager.default.fileExists(atPath: path)
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(exists ? .green : .red)
        }
    }
}
