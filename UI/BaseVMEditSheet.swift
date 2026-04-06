import SwiftUI

struct BaseVMEditSheet: View {
    let baseVM: VirtualMachine
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var templateStore: PackerTemplateStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var description: String
    @State private var defaultUsername: String
    @State private var sshPassword: String = ""
    @State private var isBaseVM: Bool = true
    @State private var osName: MacOSRelease.Name
    @State private var osVersion: String
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false

    private var versionList: [String] {
        sofaVersions.isEmpty ? osName.fallbackVersions : sofaVersions
    }

    // Template selection (v5: UUID-based)
    enum TemplateSource { case none, library, customPath }
    @State private var templateSource: TemplateSource
    @State private var selectedTemplateID: UUID?
    @State private var customTemplatePath: String
    @State private var isPresentingTemplatePicker = false

    // Vars file selection
    @State private var selectedVarsFileID: UUID?

    init(baseVM: VirtualMachine) {
        self.baseVM = baseVM
        _displayName        = State(initialValue: baseVM.displayName)
        _description        = State(initialValue: baseVM.description)
        _defaultUsername    = State(initialValue: baseVM.sshUsername)
        _isBaseVM           = State(initialValue: baseVM.isBaseVM)
        _osName             = State(initialValue: baseVM.osName)
        _osVersion          = State(initialValue: baseVM.osVersion)
        _selectedTemplateID = State(initialValue: baseVM.customTemplateID)
        _selectedVarsFileID = State(initialValue: baseVM.customVarsFileID)
        _customTemplatePath = State(initialValue: baseVM.customTemplatePath ?? "")
        // Infer source from stored values
        if baseVM.customTemplateID != nil {
            _templateSource = State(initialValue: .library)
        } else if baseVM.customTemplatePath != nil {
            _templateSource = State(initialValue: .customPath)
        } else {
            _templateSource = State(initialValue: .none)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit \"\(baseVM.name)\"").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Identity") {
                    LabeledContent("Display name") {
                        TextField("", text: $displayName,
                                  prompt: Text(baseVM.name).foregroundStyle(.secondary))
                    }
                    LabeledContent("Tart name") {
                        Text(baseVM.name)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Description") {
                        TextField("", text: $description,
                                  prompt: Text("What is this base VM for?").foregroundStyle(.secondary),
                                  axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                Section("SSH Credentials") {
                    LabeledContent("Username") {
                        TextField("", text: $defaultUsername,
                                  prompt: Text("e.g. baker").foregroundStyle(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Password") {
                        SecureField("", text: $sshPassword,
                                    prompt: Text("stored in Keychain").foregroundStyle(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    if baseVM.isOCIBased {
                        LabeledContent("Category") {
                            Text("Base VM (OCI — locked)").foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle("Use as Base VM", isOn: $isBaseVM)
                    }
                } header: { Text("Category") }
                  footer: { Text(isBaseVM
                    ? "Base VMs can be cloned but not started."
                    : "Setting to Working VM will move this to the Virtual Machines view.") }

                // Template — only for local, unbuilt VMs
                if baseVM.vmSource == .local && baseVM.buildStatus != .ready {
                    Section {
                        Picker("Source", selection: $templateSource) {
                            Text("None (auto-generate)").tag(TemplateSource.none)
                            Text("From library").tag(TemplateSource.library)
                            Text("Custom file path").tag(TemplateSource.customPath)
                        }
                        .pickerStyle(.radioGroup)

                        switch templateSource {
                        case .none:
                            Text("Oven will auto-generate a Base Template.")
                                .foregroundStyle(.secondary)
                        case .library:
                            let options = templateStore.customFullTemplates
                            if options.isEmpty {
                                Text("No custom templates in library yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Template", selection: $selectedTemplateID) {
                                    Text("Select…").tag(Optional<UUID>.none)
                                    ForEach(options) { tmpl in
                                        Text(tmpl.displayName.isEmpty ? tmpl.filename : tmpl.displayName)
                                            .tag(Optional(tmpl.id))
                                    }
                                }
                            }
                        case .customPath:
                            HStack(spacing: 6) {
                                TextField("", text: $customTemplatePath,
                                          prompt: Text("/path/to/template.pkr.hcl").foregroundStyle(.secondary))
                                Button("Browse…") { isPresentingTemplatePicker = true }
                                    .controlSize(.small)
                            }
                        }
                    } header: { Text("Packer Template") }
                      footer: { Text("Library templates are custom .pkr.hcl files from your Packer Templates library.") }
                    .fileImporter(isPresented: $isPresentingTemplatePicker,
                                  allowedContentTypes: [.init(filenameExtension: "hcl") ?? .data]) { result in
                        if let url = try? result.get() { customTemplatePath = url.path }
                    }

                    Section {
                        let varsFiles = templateStore.varsFiles
                        Picker("Variables file", selection: $selectedVarsFileID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(varsFiles) { tmpl in
                                Text(tmpl.displayName.isEmpty ? tmpl.filename : tmpl.displayName)
                                    .tag(Optional(tmpl.id))
                            }
                        }
                        if selectedVarsFileID != nil {
                            Label("Vars files can override hardware and credentials. Keychain credentials are always injected securely at build time.",
                                  systemImage: "lock.shield")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } header: { Text("Template Variables") }
                      footer: { Text("Optional. A vars file can override CPU, memory, disk, and other template settings.") }
                }

                Section("OS") {
                    Picker("macOS", selection: $osName) {
                        ForEach(MacOSRelease.Name.allCases, id: \.self) { release in
                            Text(release.displayLabel).tag(release)
                        }
                    }
                    .onChange(of: osName) { _, newOS in
                        osVersion = ""
                        Task { await loadVersions(for: newOS) }
                    }
                    HStack {
                        Picker("Version", selection: $osVersion) {
                            Text("Unknown").tag("")
                            ForEach(versionList, id: \.self) { v in Text(v).tag(v) }
                        }
                        if isFetchingVersions {
                            ProgressView().controlSize(.mini).padding(.leading, 4)
                        }
                    }
                }

                Section("Info") {
                    if baseVM.vmSource == .local {
                        LabeledContent("Hardware", value: "\(baseVM.cpuCount) CPU · \(baseVM.memoryGB) GB · \(baseVM.diskGB) GB")
                    }
                    LabeledContent("Source", value: baseVM.vmSource.rawValue)
                    if let built = baseVM.builtAt {
                        LabeledContent("Built", value: built.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 300)
        .task { await loadVersions(for: osName) }
    }

    private func loadVersions(for release: MacOSRelease.Name) async {
        isFetchingVersions = true
        sofaVersions = await SOFAService.shared.versions(for: release)
        isFetchingVersions = false
    }

    private func save() {
        let applyTemplate: (inout VirtualMachine) -> Void = { v in
            switch templateSource {
            case .none:
                v.customTemplateID    = nil
                v.customTemplatePath  = nil
            case .library:
                v.customTemplateID    = selectedTemplateID
                v.customTemplatePath  = nil
            case .customPath:
                v.customTemplateID    = nil
                v.customTemplatePath  = customTemplatePath.isEmpty ? nil : customTemplatePath
            }
            v.customVarsFileID = selectedVarsFileID
        }

        baseVMStore.update(id: baseVM.id) { v in
            v.displayName  = displayName.trimmingCharacters(in: .whitespaces)
            v.description  = description
            v.sshUsername  = defaultUsername.trimmingCharacters(in: .whitespaces)
            v.sshPassword  = sshPassword.isEmpty ? nil : sshPassword
            v.osName       = osName
            v.osVersion    = osVersion
            if !v.isOCIBased { v.isBaseVM = isBaseVM }
            applyTemplate(&v)
        }
        vmStore.update(id: baseVM.id) { v in
            v.osName    = osName
            v.osVersion = osVersion
            if !v.isOCIBased { v.isBaseVM = isBaseVM }
            applyTemplate(&v)
        }
        dismiss()
    }
}
