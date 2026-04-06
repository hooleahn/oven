import SwiftUI


struct NewBaseVMSheet: View {
    var preselectedIPSWURL: URL? = nil   // pre-populate from macOS Installers

    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var templateStore: PackerTemplateStore
    @Environment(\.dismiss) var dismiss

    // MDM enrollment profiles loaded from disk
    @State private var mdmProfiles: [MDMProfile] = []
    @State private var mdmServers:  [MDMServer]  = []

    // Template selection (v5: UUID-based)
    enum TemplateSource { case none, library, customPath }
    @State private var templateSource: TemplateSource = .none
    @State private var selectedTemplateID: UUID? = nil
    @State private var externalTemplatePath: String = ""
    @State private var isPresentingExternalTemplatePicker = false

    // Vars file selection
    @State private var selectedVarsFileID: UUID? = nil

    @State private var osName:   MacOSRelease.Name = .sequoia
    @State private var osVersion = ""
    @State private var customIPSWPath = ""       // manual file path
    @State private var customIPSWURL  = ""       // remote URL
    @State private var isPresentingIPSWPicker = false
    @State private var liveFirmwares: [IPSWFirmware] = []
    @State private var isFetchingVersions = false
    enum IPSWSource { case auto, customPath, remoteURL }
    @State private var ipswSource: IPSWSource = .auto
    // Hardware — seeded from Preferences defaults on appear
    @State private var settings = AppSettings.load()
    @AppStorage("defaultCPUCount")       private var defaultCPU: Int = 4
    @AppStorage("defaultMemoryGB")       private var defaultMemory: Int = 8
    @AppStorage("defaultDiskGB")         private var defaultDisk: Int = 80
    @AppStorage("defaultPackerUsername") private var defaultUsername: String = "baker"
    @State private var username = "baker"
    @State private var password = "baker"
    @State private var cpuCount  = 4
    @State private var memoryGB  = 8
    @State private var diskGB    = 80
    @State private var installRosetta         = true
    @State private var installHomebrew        = true
    @State private var enableSSHDaemon        = true
    @State private var enableAutoLogin        = true
    @State private var enablePasswordlessSudo = true
    @State private var xcodeVersion  = ""
    @State private var enableXcode   = false
    @State private var selectedMDMProfileID: UUID? = nil

    private let cpuOptions  = [2, 4, 6, 8, 10, 12, 16]
    private let memOptions  = [4, 8, 12, 16, 24, 32, 48, 64]
    private let diskOptions = [40, 60, 80, 100, 120, 150, 200, 250, 500]

    var previewName: String { VirtualMachine.uniqueAutoName(osName: osName, version: osVersion, existing: baseVMStore.baseVMs) }

    var resolvedIPSWPath: String? {
        switch ipswSource {
        case .auto:         return nil
        case .customPath:   return customIPSWPath.isEmpty ? nil : customIPSWPath
        case .remoteURL:    return nil   // passed as ipswURL override separately
        }
    }

    var resolvedIPSWURL: String? {
        guard ipswSource == .remoteURL, !customIPSWURL.isEmpty else { return nil }
        return customIPSWURL
    }

    var canCreate: Bool {
        guard !osVersion.isEmpty else { return false }
        switch ipswSource {
        case .auto:         return true
        case .customPath:   return !customIPSWPath.isEmpty
        case .remoteURL:    return !customIPSWURL.isEmpty
        }
    }

    var selectedMDMProfile: MDMProfile? {
        mdmProfiles.first(where: { $0.id == selectedMDMProfileID })
    }
    var selectedMDMServer: MDMServer? {
        guard let profile = selectedMDMProfile else { return nil }
        return mdmServers.first(where: { $0.id == profile.serverID })
    }

    var body: some View {
        VStack(spacing: 0) {
        sheetToolbar
        Divider()

            Form {
                // Name preview
                Section {
                    LabeledContent("Name preview") {
                        Text(previewName)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Generated name") }
                  footer: { Text("Names are generated automatically and cannot be customised.") }

                // macOS version
                Section("macOS version") {
                    Picker("OS", selection: $osName) {
                        ForEach(MacOSRelease.Name.allCases, id: \.self) {
                            Text($0.displayLabel).tag($0)
                        }
                    }
                    HStack {
                        Picker("Version", selection: $osVersion) {
                            Text("Select a version…").tag("")
                            ForEach(versionList, id: \.self) { Text($0).tag($0) }
                        }
                        if isFetchingVersions {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .onChange(of: osName) { _, _ in osVersion = ""; customIPSWPath = ""; customIPSWURL = ""; selectedTemplateID = nil; Task { await fetchLiveVersions() } }
                    .onChange(of: osVersion) { _, _ in
                        selectedTemplateID = nil  // reset when OS version changes
                    }
                }

                // IPSW source
                Section("IPSW source") {
                    Picker("Source", selection: $ipswSource) {
                        Text("Download automatically (via \(settings.ipswDownloadMode == .mistCli ? "mist-cli" : "ipsw.me"))").tag(IPSWSource.auto)
                        Text("Custom file path").tag(IPSWSource.customPath)
                        Text("Download from URL").tag(IPSWSource.remoteURL)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: ipswSource) { _, _ in
                        customIPSWPath = ""; customIPSWURL = ""
                    }

                    switch ipswSource {
                    case .auto:
                        Text("If the IPSW has already been downloaded to the Installers library it won't be downloaded again.")
                            .font(.caption).foregroundStyle(.secondary)

                    case .customPath:
                        HStack(spacing: 6) {
                            TextField("", text: $customIPSWPath,
                                      prompt: Text("/path/to/macOS.ipsw").foregroundColor(.secondary))
                            Button("Browse…") { isPresentingIPSWPicker = true }
                                .controlSize(.small)
                        }
                        .fileImporter(isPresented: $isPresentingIPSWPicker,
                                      allowedContentTypes: [.init(filenameExtension: "ipsw") ?? .data]) { result in
                            if let url = try? result.get() { customIPSWPath = url.path }
                        }
                    case .remoteURL:
                        TextField("", text: $customIPSWURL,
                                  prompt: Text("https://example.com/macOS.ipsw").foregroundColor(.secondary))
                        Text("Oven will download the IPSW to the configured IPSW storage folder before building.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Credentials
                Section("Default credentials") {
                    LabeledContent("Username") {
                        TextField("", text: $username, prompt: Text("e.g. baker").foregroundColor(.secondary))
                    }
                    LabeledContent("Password") {
                        SecureField("baker", text: $password)
                    }
                }

                // Hardware
                Section("Hardware") {
                    Picker("CPU cores", selection: $cpuCount) {
                        ForEach(cpuOptions, id: \.self) { Text("\($0) cores").tag($0) }
                    }
                    Picker("Memory", selection: $memoryGB) {
                        ForEach(memOptions, id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    Picker("Disk size", selection: $diskGB) {
                        ForEach(diskOptions, id: \.self) { Text("\($0) GB").tag($0) }
                    }
                }

                // Provisioning
                Section("Post-build provisioning") {
                    Toggle("Install Rosetta 2",    isOn: $installRosetta)
                    Toggle("Install Homebrew",     isOn: $installHomebrew)
                    Toggle("Enable SSH",           isOn: $enableSSHDaemon)
                    Toggle("Enable auto-login",    isOn: $enableAutoLogin)
                    Toggle("Passwordless sudo",    isOn: $enablePasswordlessSudo)
                    Toggle("Install Xcode",        isOn: $enableXcode)
                    if enableXcode {
                        LabeledContent("Xcode version") {
                            TextField("", text: $xcodeVersion, prompt: Text("e.g. 16.3").foregroundColor(.secondary))
                        }
                    }
                }

                // Packer template
                Section {
                    Picker("Template", selection: $templateSource) {
                        Text("None (auto-generate)").tag(TemplateSource.none)
                        Text("From library").tag(TemplateSource.library)
                        Text("Custom file path").tag(TemplateSource.customPath)
                    }
                    .pickerStyle(.radioGroup)

                    switch templateSource {
                    case .none:
                        Text("Oven will generate a Base Template for \(osName.rawValue) \(osVersion).")
                            .foregroundStyle(.secondary)
                    case .library:
                        let matching = templateStore.fullTemplates(for: osName.rawValue, version: osVersion)
                        let all      = templateStore.customFullTemplates
                        let options  = matching.isEmpty ? all : matching
                        if options.isEmpty {
                            Text("No templates in library. Create one in \(theme.recipes).")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Template", selection: $selectedTemplateID) {
                                Text("Select…").tag(Optional<UUID>.none)
                                ForEach(options) { tmpl in
                                    VStack(alignment: .leading) {
                                        Text(tmpl.displayName.isEmpty ? tmpl.filename : tmpl.displayName)
                                        if !tmpl.osVersion.isEmpty {
                                            Text(tmpl.osName + " " + tmpl.osVersion)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .tag(Optional(tmpl.id))
                                }
                            }
                        }
                    case .customPath:
                        HStack(spacing: 6) {
                            TextField("", text: $externalTemplatePath,
                                      prompt: Text("/path/to/template.pkr.hcl").foregroundStyle(.secondary))
                            Button("Browse…") { isPresentingExternalTemplatePicker = true }
                                .controlSize(.small)
                        }
                        .fileImporter(isPresented: $isPresentingExternalTemplatePicker,
                                      allowedContentTypes: [.init(filenameExtension: "hcl") ?? .data]) { result in
                            if let url = try? result.get() { externalTemplatePath = url.path }
                        }
                    }
                } header: { Text("Packer Template") }
                  footer: { Text("Templates filtered to \(osName.rawValue) \(osVersion). Change OS/version above to see more.") }

                // Template Variables
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
                        Label("Vars files can override hardware and credentials set above. Keychain credentials are always injected securely at build time.",
                              systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: { Text("Template Variables") }
                  footer: { Text("Optional. A vars file can override CPU, memory, disk, VM name, and other settings defined in the template.") }

                // MDM enrollment
                Section {
                    Picker("Enrollment profile", selection: $selectedMDMProfileID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(mdmProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    if let server = selectedMDMServer, let profile = selectedMDMProfile {
                        LabeledContent("Server") { Text(server.friendlyName).foregroundStyle(.secondary) }
                        LabeledContent("Invitation ID") {
                            Text(profile.invitationID.isEmpty ? "Not set" : profile.invitationID)
                                .foregroundStyle(profile.invitationID.isEmpty ? .red : .secondary)
                        }
                        if profile.invitationID.isEmpty {
                            Label("Set an Invitation ID in MDM Enrollment first.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if mdmProfiles.isEmpty {
                        Text("No enrollment profiles configured. Add one in MDM Enrollment.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("MDM enrollment") }
                  footer: { Text("If selected, the enrollment profile and invitation ID will be baked into the Packer template.") }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 580)
        .task {
            // Seed hardware + credentials from Preferences defaults
            cpuCount = defaultCPU
            memoryGB = defaultMemory
            diskGB   = defaultDisk
            username = defaultUsername
            password = KeychainService.retrieve(key: "defaults.packer.password") ?? "baker"
            loadMDMData()
            await fetchLiveVersions()
            // Snap version picker to first valid value after versions load
            let versions = versionList
            if osVersion.isEmpty || !versions.contains(osVersion), let first = versions.first {
                osVersion = first
            }
            if let url = preselectedIPSWURL { detectOS(from: url) }
        }
        .onChange(of: liveFirmwares) { _, _ in
            // After versions load, snap any invalid/empty selection to the first available
            let versions = versionList
            if !versions.isEmpty && !versions.contains(osVersion) {
                osVersion = versions[0]
            }
        }
    }

    private var versionList: [String] {
        let major = osName.majorVersion
        let live = liveFirmwares
            .filter { $0.majorVersion == major }
            .map { $0.version }
        if live.isEmpty { return osName.fallbackVersions }
        // Deduplicate (API may list multiple builds per version string)
        var seen = Set<String>()
        return live.filter { seen.insert($0).inserted }
    }


    // MARK: - Subviews

    @ViewBuilder private var sheetToolbar: some View {
        HStack {
            Text(theme.newBaseVM).font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            Button(theme.build) { create() }
                .buttonStyle(.borderedProminent).disabled(!canCreate)
        }
        .padding(16).background(.bar)
    }

    private func fetchLiveVersions(force: Bool = false) async {
        // Only hit the network when cache is stale (>24h) or force-refreshed
        let fresh = await IPSWService.shared.isCacheFresh
        if !force && fresh && !liveFirmwares.isEmpty { return }
        isFetchingVersions = true
        if let results = try? await IPSWService.shared.listFirmware() {
            liveFirmwares = results
        }
        isFetchingVersions = false
    }

    private func create() {
        var vm = VirtualMachine(
            name: VirtualMachine.uniqueAutoName(osName: osName, version: osVersion,
                                                existing: baseVMStore.baseVMs),
            isBaseVM: true
        )
        vm.osName              = osName
        vm.osVersion           = osVersion
        vm.macOSVersion        = "macOS \(osName.rawValue) \(osVersion)"
        vm.ipswLocalPath       = resolvedIPSWPath
        vm.ipswRemoteURL       = resolvedIPSWURL
        vm.sshUsername         = username
        vm.cpuCount            = cpuCount
        vm.memoryGB            = memoryGB
        vm.diskGB              = diskGB
        vm.installRosetta      = installRosetta
        vm.installHomebrew     = installHomebrew
        vm.enableSSHDaemon     = enableSSHDaemon
        vm.enableAutoLogin     = enableAutoLogin
        vm.enablePasswordlessSudo = enablePasswordlessSudo
        vm.xcodeVersion        = enableXcode && !xcodeVersion.isEmpty ? xcodeVersion : nil
        vm.mdmProfileID        = selectedMDMProfileID
        vm.sshPassword         = password.isEmpty ? nil : password
        vm.vmSource            = .local
        vm.buildStatus         = .notBuilt
        // Template selection (v5: UUID or raw path)
        switch templateSource {
        case .none:
            vm.customTemplateID = nil
            vm.customTemplatePath = nil
        case .library:
            vm.customTemplateID = selectedTemplateID
            vm.customTemplatePath = nil
        case .customPath:
            vm.customTemplateID = nil
            vm.customTemplatePath = externalTemplatePath.isEmpty ? nil : externalTemplatePath
        }
        vm.customVarsFileID = selectedVarsFileID
        baseVMStore.add(vm)
        dismiss()
        Task { await baseVMStore.build(baseVM: vm) }
    }

    private func detectOS(from url: URL) {
        ipswSource = .customPath
        customIPSWPath = url.path
        let filename = url.deletingPathExtension().lastPathComponent
        let parts = filename.components(separatedBy: CharacterSet(charactersIn: "-_"))
        for part in parts {
            let nums = part.components(separatedBy: ".")
            if nums.count >= 2, let major = Int(nums[0]), major >= 12 {
                osVersion = part
                switch major {
                case 26: osName = .tahoe
                case 15: osName = .sequoia
                case 14: osName = .sonoma
                case 13: osName = .ventura
                case 12: osName = .monterey
                default: break
                }
                return
            }
        }
    }

    private func loadMDMData() {
        _ = AppSettings.defaultLocalStorageRoot
        let loaded = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [MDMProfile]())
        if !loaded.isEmpty {
            mdmProfiles = loaded
        }
        let sloaded = AppDatabase.shared.readOrDefault(.mdmServers, default: [MDMServer]())
        if !sloaded.isEmpty {
            mdmServers = sloaded
        }
    }

}
