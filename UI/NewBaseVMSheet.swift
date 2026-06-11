import SwiftUI

// MARK: - NewBaseVMSheet
//
// Two-path Base VM creation sheet:
//   Path A — From Template: pick a library or custom-path template, build.
//   Path B — Build Manually: IPSW source → hardware → (optional) Setup Assistant
//            automation → Review generated HCL → build.

struct NewBaseVMSheet: View {
    var preselectedIPSWURL: URL? = nil
    var preselectedInstaller: Installer? = nil

    @Environment(BaseVMStore.self) private var baseVMStore
    @Environment(AppTheme.self) private var theme
    @Environment(PackerTemplateStore.self) private var templateStore
    @Environment(BuildingBlockStore.self) private var blockStore
    @Environment(InstallerStore.self) private var installerStore
    @Environment(\.dismiss) var dismiss

    // MARK: - Top-level path selection
    enum BuildPath { case fromTemplate, manually }
    @State private var buildPath: BuildPath = .manually

    // MARK: - Common fields
    @State private var displayName   = ""
    @State private var osName: MacOSRelease.Name = .sequoia
    @State private var versionPickerSel = ""
    @State private var customVersionText = ""
    @State private var isBetaOS = false
    @State private var betaLabel = ""
    @State private var customOSMajorVersion = ""
    @State private var customOSReleaseName = ""
    @State private var liveFirmwares: [IPSWFirmware] = []
    @State private var isFetchingVersions = false
    @State private var majorVersionError: String? = nil
    @State private var customVersionError: String? = nil

    private static let customVersionSentinel = "__custom__"
    private static let ipswVersionRegex = /^\d+(\.\d+)*$/

    // MARK: - From-template path
    enum TemplateSource { case library, customPath }
    @State private var templateSource: TemplateSource = .library
    @State private var selectedTemplateID: UUID? = nil
    @State private var externalTemplatePath = ""
    @State private var isPresentingExternalTemplatePicker = false
    @State private var selectedVarsFileID: UUID? = nil
    // Template-path credentials (stored as VM metadata)
    @State private var tmplUsername = "admin"
    @State private var tmplPassword = "admin"
    @State private var tmplCPU = 4
    @State private var tmplMemory = 8
    @State private var tmplDisk = 80
    // MDM
    @State private var mdmProfiles: [MDMProfile] = []
    @State private var mdmServers:  [MDMServer]  = []
    @State private var selectedMDMProfileID: UUID? = nil

    // MARK: - Manual-build path (multi-step)
    enum ManualStep { case ipsw, hardware, automation, review }
    @State private var manualStep: ManualStep = .ipsw

    // IPSW source
    enum IPSWSourceChoice { case auto, filePath, remoteURL, customInstaller }
    @State private var ipswChoice: IPSWSourceChoice = .auto
    @State private var customIPSWPath = ""
    @State private var customIPSWURL  = ""
    @State private var isPresentingIPSWPicker = false
    @State private var selectedCustomInstallerID: UUID? = nil
    @State private var settings = AppSettings.load()

    // Hardware
    @AppStorage("defaultCPUCount")  private var defaultCPU: Int = 4
    @AppStorage("defaultMemoryGB")  private var defaultMemory: Int = 8
    @AppStorage("defaultDiskGB")    private var defaultDisk: Int = 80
    @State private var cpuCount = 4
    @State private var memoryGB = 8
    @State private var diskGB   = 80

    // Setup Assistant automation
    @State private var automateSetupAssistant = false
    @State private var bootCommandID: UUID? = nil
    @State private var manualUsername = "admin"
    @State private var manualPassword = "admin"
    @State private var provisioning = ProvisioningOptions()
    // MDM enrollment for manual path (separate from template path's selectedMDMProfileID)
    @State private var manualMDMProfileID: UUID? = nil

    // Review
    @State private var saveToTemplates = false
    @State private var generatedHCL    = ""

    // MARK: - AppStorage for defaults
    @AppStorage("defaultPackerUsername") private var defaultUsername: String = "admin"

    private let cpuOptions  = [2, 4, 6, 8, 10, 12, 16]
    private let memOptions  = [4, 8, 12, 16, 24, 32, 48, 64]
    private let diskOptions = [40, 60, 80, 100, 120, 150, 200, 250, 500]

    init(preselectedIPSWURL: URL? = nil, preselectedInstaller: Installer? = nil) {
        self.preselectedIPSWURL = preselectedIPSWURL
        self.preselectedInstaller = preselectedInstaller
        if let m = preselectedInstaller?.osMetadata {
            _osName = State(initialValue: m.osName)
            _isBetaOS = State(initialValue: m.isBeta)
            _betaLabel = State(initialValue: m.betaLabel)
            _customOSMajorVersion = State(initialValue: m.customMajorVersion)
            _customOSReleaseName = State(initialValue: m.customReleaseName)
            // Pre-seed the version picker so it shows immediately, before live data loads.
            let version = m.osVersion.isEmpty ? m.customMajorVersion : m.osVersion
            if !version.isEmpty {
                _versionPickerSel = State(initialValue: version)
            }
            print("[NewBaseVM] init — osName=\(m.osName) osVersion='\(m.osVersion)' customMajorVersion='\(m.customMajorVersion)' → seeding versionPickerSel='\(version)'")
        } else {
            print("[NewBaseVM] init — no preselectedInstaller")
        }
    }

    // MARK: - Computed helpers

    private var versionList: [String] {
        let major = osName.majorVersion
        let live = liveFirmwares.filter { $0.majorVersion == major }.map { $0.version }
        if live.isEmpty { return osName.fallbackVersions }
        var seen = Set<String>()
        return live.filter { seen.insert($0).inserted }
    }

    private var resolvedOSVersion: String {
        versionPickerSel == Self.customVersionSentinel ? customVersionText : versionPickerSel
    }

    private var tartName: String {
        VirtualMachine.uniqueAutoName(osName: osName, version: resolvedOSVersion,
                                     existing: baseVMStore.baseVMs)
    }

    private var canProceedFromTemplate: Bool {
        guard !resolvedOSVersion.isEmpty else { return false }
        switch templateSource {
        case .library:    return selectedTemplateID != nil
        case .customPath: return !externalTemplatePath.isEmpty
        }
    }

    private var canProceedIPSW: Bool {
        let hasVersion = !resolvedOSVersion.isEmpty
        switch ipswChoice {
        case .auto:             return hasVersion && osName != .any && osName != .custom
        case .filePath:         return !customIPSWPath.isEmpty && hasVersion
        case .remoteURL:        return !customIPSWURL.isEmpty && hasVersion
        case .customInstaller:
            guard let id = selectedCustomInstallerID,
                  let inst = installerStore.customInstallers.first(where: { $0.id == id })
            else { return false }
            return inst.fileExists
        }
    }

    private var resolvedIPSWSource: IPSWSource {
        switch ipswChoice {
        case .auto:      return .auto
        case .filePath:  return .filePath(URL(fileURLWithPath: customIPSWPath))
        case .remoteURL: return .url(customIPSWURL)
        case .customInstaller:
            if let id = selectedCustomInstallerID,
               let inst = installerStore.customInstallers.first(where: { $0.id == id }),
               let url = inst.fileURL {
                return .filePath(url)
            }
            return .auto
        }
    }

    private var selectedCustomInstaller: Installer? {
        guard let id = selectedCustomInstallerID else { return nil }
        return installerStore.customInstallers.first { $0.id == id }
    }

    private var selectedBootCommandBlock: BootCommandBlock? {
        guard let id = bootCommandID else { return nil }
        return blockStore.bootCommand(id: id)
    }

    private var selectedMDMProfile: MDMProfile? {
        mdmProfiles.first { $0.id == selectedMDMProfileID }
    }
    private var selectedMDMServer: MDMServer? {
        guard let p = selectedMDMProfile, let sid = p.serverID else { return nil }
        return mdmServers.first { $0.id == sid }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sheetToolbar
            Divider()
            contentArea
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 540)
        .task {
            cpuCount  = defaultCPU
            memoryGB  = defaultMemory
            diskGB    = defaultDisk
            tmplCPU   = defaultCPU
            tmplMemory = defaultMemory
            tmplDisk  = defaultDisk
            manualUsername = defaultUsername
            tmplUsername   = defaultUsername
            manualPassword = KeychainService.retrieve(key: "defaults.packer.password") ?? "admin"
            tmplPassword   = KeychainService.retrieve(key: "defaults.packer.password") ?? "admin"
            loadMDMData()
            print("[NewBaseVM] task — before fetchLiveVersions, preselectedInstaller=\(preselectedInstaller != nil ? "present" : "nil") versionPickerSel='\(versionPickerSel)'")
            await fetchLiveVersions()
            print("[NewBaseVM] task — after fetchLiveVersions, preselectedInstaller=\(preselectedInstaller != nil ? "present" : "nil") versionPickerSel='\(versionPickerSel)' liveFirmwares.count=\(liveFirmwares.count)")
            if let installer = preselectedInstaller {
                // onChange(of: liveFirmwares) already ran while fetching; call again to
                // ensure the version is confirmed against the now-complete live list.
                applyVersionFromInstaller(installer)
            } else {
                let versions = versionList
                if versionPickerSel.isEmpty || (!versions.contains(versionPickerSel) && versionPickerSel != Self.customVersionSentinel),
                   let first = versions.first {
                    versionPickerSel = first
                }
                if let url = preselectedIPSWURL {
                    detectOS(from: url)
                }
            }
        }
        .onChange(of: liveFirmwares) { _, _ in
            if let installer = preselectedInstaller {
                print("[NewBaseVM] onChange(liveFirmwares) — preselectedInstaller present, calling applyVersionFromInstaller. versionPickerSel before='\(versionPickerSel)'")
                // Live list just arrived; confirm the preselected version against it.
                applyVersionFromInstaller(installer)
                print("[NewBaseVM] onChange(liveFirmwares) — versionPickerSel after='\(versionPickerSel)'")
            } else {
                print("[NewBaseVM] onChange(liveFirmwares) — NO preselectedInstaller, versionPickerSel='\(versionPickerSel)' versionList=\(versionList.prefix(3))")
                let versions = versionList
                if !versions.isEmpty && !versions.contains(versionPickerSel) && versionPickerSel != Self.customVersionSentinel {
                    versionPickerSel = versions[0]
                    print("[NewBaseVM] onChange(liveFirmwares) — set versionPickerSel='\(versionPickerSel)'")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder private var sheetToolbar: some View {
        HStack {
            Text(theme.newBaseVM).font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            if buildPath == .fromTemplate {
                Button(theme.build) { createFromTemplate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceedFromTemplate)
            } else {
                manualNavButtons
            }
        }
        .padding(16).background(.bar)
    }

    @ViewBuilder private var manualNavButtons: some View {
        switch manualStep {
        case .ipsw:
            Button("Next: Hardware") { manualStep = .hardware }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedIPSW)
        case .hardware:
            Button("Back") { manualStep = .ipsw }
            Button("Next: Automation") { manualStep = .automation }
                .buttonStyle(.borderedProminent)
        case .automation:
            Button("Back") { manualStep = .hardware }
            Button("Review") { buildReviewHCL(); manualStep = .review }
                .buttonStyle(.borderedProminent)
        case .review:
            Button("Back") { manualStep = .automation }
            Button(theme.build) { createManual() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Content area

    @ViewBuilder private var contentArea: some View {
        Form {
            // Path picker + common OS/version fields — shown at the top of all steps
            pathAndOSSection

            switch buildPath {
            case .fromTemplate:
                templatePathContent
            case .manually:
                manualContent
            }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: buildPath)
        .animation(.easeInOut(duration: 0.2), value: manualStep)
    }

    // MARK: - Shared top section

    @ViewBuilder private var pathAndOSSection: some View {
        Section {
            Picker("Build from", selection: $buildPath) {
                Text("Build manually").tag(BuildPath.manually)
                Text("Template").tag(BuildPath.fromTemplate)
            }
            .pickerStyle(.segmented)
            .onChange(of: buildPath) { _, _ in manualStep = .ipsw }
        }

        Section("macOS version") {
            Picker("OS", selection: $osName) {
                ForEach(MacOSRelease.Name.allCases.filter { $0 != .unknown && $0 != .any }, id: \.self) {
                    Text($0.displayLabel).tag($0)
                }
            }
            .onChange(of: osName) { old, new in
                print("[NewBaseVM] onChange(osName) — \(old) → \(new), resetting versionPickerSel")
                versionPickerSel = ""; customVersionText = ""
                customOSMajorVersion = ""; customOSReleaseName = ""
                customIPSWPath = ""; customIPSWURL = ""
                selectedTemplateID = nil
                majorVersionError = nil; customVersionError = nil
                Task { await fetchLiveVersions() }
            }
            if osName == .custom {
                LabeledContent("Major version") {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("e.g. 27", text: $customOSMajorVersion)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: customOSMajorVersion) { _, v in
                                let filtered = v.filter { $0.isNumber }
                                if filtered != v { customOSMajorVersion = filtered }
                                majorVersionError = (!filtered.isEmpty && Int(filtered) == nil)
                                    ? "Must be a positive integer" : nil
                            }
                        if let err = majorVersionError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                LabeledContent("Release name") {
                    TextField("e.g. Yuba", text: $customOSReleaseName)
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack {
                Picker("Version", selection: $versionPickerSel) {
                    Text("Select a version…").tag("")
                    ForEach(versionList, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Custom…").tag(Self.customVersionSentinel)
                }
                .onChange(of: versionPickerSel) { _, sel in
                    if sel != Self.customVersionSentinel {
                        customVersionText = ""
                        selectedTemplateID = nil
                    }
                }
                if isFetchingVersions { ProgressView().controlSize(.mini) }
            }
            if versionPickerSel == Self.customVersionSentinel {
                LabeledContent("Custom version") {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("e.g. 26.5", text: $customVersionText)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: customVersionText) { _, v in
                                customVersionError = (!v.isEmpty && v.wholeMatch(of: Self.ipswVersionRegex) == nil)
                                    ? "Use digits and dots only" : nil
                            }
                        if let err = customVersionError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            Toggle("Beta OS", isOn: $isBetaOS)
            if isBetaOS {
                LabeledContent("Beta label") {
                    TextField("e.g. Beta 1, RC 2", text: $betaLabel)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - From-template content

    @ViewBuilder private var templatePathContent: some View {
        // Display name
        Section("Display name") {
            TextField("", text: $displayName,
                      prompt: Text("e.g. Sequoia 15.4 CI").foregroundStyle(.secondary))
        }

        // Template source
        Section {
            Picker("Template source", selection: $templateSource) {
                Text("From library").tag(TemplateSource.library)
                Text("Custom file path").tag(TemplateSource.customPath)
            }
            .pickerStyle(.radioGroup)

            switch templateSource {
            case .library:
                let matching = templateStore.fullTemplates(for: osName.rawValue, version: resolvedOSVersion)
                let all      = templateStore.customFullTemplates
                let options  = matching.isEmpty ? all : matching
                if options.isEmpty {
                    Text("No templates in library. Create one in \(theme.recipes).")
                        .font(.caption).foregroundStyle(.secondary)
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
                            }.tag(Optional(tmpl.id))
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
        } header: { Text("Packer template") }
          footer: { Text("Templates filtered to \(osName.rawValue) \(resolvedOSVersion). Change OS/version above to see more.") }

        // Vars file
        Section {
            let varsFiles = templateStore.varsFiles
            Picker("Variables file", selection: $selectedVarsFileID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(varsFiles) { tmpl in
                    Text(tmpl.displayName.isEmpty ? tmpl.filename : tmpl.displayName).tag(Optional(tmpl.id))
                }
            }
        } header: { Text("Template variables") }
          footer: { Text("Optional. A vars file can override CPU, memory, disk, and other settings in the template.") }

        // Credentials
        Section("Default credentials") {
            LabeledContent("Username") {
                TextField("", text: $tmplUsername, prompt: Text("e.g. admin").foregroundStyle(.secondary))
            }
            LabeledContent("Password") {
                SecureField("admin", text: $tmplPassword)
            }
        }

        // Hardware
        Section("Hardware") {
            Picker("CPU cores", selection: $tmplCPU) {
                ForEach(cpuOptions, id: \.self) { Text("\($0) cores").tag($0) }
            }
            Picker("Memory", selection: $tmplMemory) {
                ForEach(memOptions, id: \.self) { Text("\($0) GB").tag($0) }
            }
            Picker("Disk size", selection: $tmplDisk) {
                ForEach(diskOptions, id: \.self) { Text("\($0) GB").tag($0) }
            }
        }

        // MDM
        if theme.mdmEnabled {
            Section {
                Picker("Enrollment profile", selection: $selectedMDMProfileID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(mdmProfiles) { p in Text(p.displayName).tag(Optional(p.id)) }
                }
                if let server = selectedMDMServer, let profile = selectedMDMProfile {
                    LabeledContent("Server") { Text(server.friendlyName).foregroundStyle(.secondary) }
                    LabeledContent("Invitation ID") {
                        Text(profile.invitationID.isEmpty ? "Not set" : profile.invitationID)
                            .foregroundStyle(profile.invitationID.isEmpty ? .red : .secondary)
                    }
                    if profile.invitationID.isEmpty {
                        Label("Set an Invitation ID in MDM Enrollment first.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if mdmProfiles.isEmpty {
                    Text("No enrollment profiles configured. Add one in MDM Enrollment.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("MDM enrollment") }
              footer: { Text("If selected, the enrollment profile and invitation ID will be built into the Packer template.") }
        }

        // Tart name preview
        Section {
            LabeledContent("Tart name") {
                Text(tartName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } footer: { Text("Names are generated automatically.") }
    }

    // MARK: - Manual build content (step-based)

    @ViewBuilder private var manualContent: some View {
        switch manualStep {
        case .ipsw:     manualIPSWStep
        case .hardware: manualHardwareStep
        case .automation: manualAutomationStep
        case .review:   manualReviewStep
        }
    }

    // MARK: Manual step 1 — IPSW source

    @ViewBuilder private var manualIPSWStep: some View {
        Section("Display name") {
            TextField("", text: $displayName,
                      prompt: Text("e.g. Sequoia 15.4 CI").foregroundStyle(.secondary))
        }

        Section {
            Picker("Source", selection: $ipswChoice) {
                Text("Download automatically (via \(settings.ipswDownloadMode == .mistCli ? "mist-cli" : "ipsw.me"))").tag(IPSWSourceChoice.auto)
                Text("Custom file path").tag(IPSWSourceChoice.filePath)
                Text("Download from URL").tag(IPSWSourceChoice.remoteURL)
                if !installerStore.customInstallers.isEmpty {
                    Text("Custom Installer library").tag(IPSWSourceChoice.customInstaller)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: ipswChoice) { _, _ in
                customIPSWPath = ""; customIPSWURL = ""
                selectedCustomInstallerID = nil
            }

            switch ipswChoice {
            case .auto:
                Text("If the IPSW has already been downloaded to the Installers library it won't be downloaded again.")
                    .font(.caption).foregroundStyle(.secondary)
            case .filePath:
                HStack(spacing: 6) {
                    TextField("", text: $customIPSWPath,
                              prompt: Text("/path/to/macOS.ipsw").foregroundStyle(.secondary))
                    Button("Browse…") { isPresentingIPSWPicker = true }.controlSize(.small)
                }
                .fileImporter(isPresented: $isPresentingIPSWPicker,
                              allowedContentTypes: [.init(filenameExtension: "ipsw") ?? .data]) { result in
                    if let url = try? result.get() {
                        customIPSWPath = url.path
                        detectOS(from: url)
                    }
                }
            case .remoteURL:
                TextField("", text: $customIPSWURL,
                          prompt: Text("https://example.com/macOS.ipsw").foregroundStyle(.secondary))
                Text("Oven will download the IPSW to the configured IPSW storage folder before building.")
                    .font(.caption).foregroundStyle(.secondary)
            case .customInstaller:
                Picker("Installer", selection: $selectedCustomInstallerID) {
                    Text("Select…").tag(Optional<UUID>.none)
                    ForEach(installerStore.customInstallers) { inst in
                        Text(inst.fileExists
                             ? "\(inst.displayName) — \(inst.osMetadata.displayString)"
                             : "\(inst.displayName) (file not found)")
                            .tag(Optional(inst.id))
                    }
                }
                .onChange(of: selectedCustomInstallerID) { _, id in
                    if let inst = installerStore.customInstallers.first(where: { $0.id == id }) {
                        let m = inst.osMetadata
                        if m.osName != .unknown { osName = m.osName }
                        if m.osName == .custom {
                            customOSReleaseName = m.customReleaseName
                            customOSMajorVersion = m.customMajorVersion
                        }
                        isBetaOS = m.isBeta
                        betaLabel = m.betaLabel
                        applyVersionFromInstaller(inst)
                    }
                }
                if let inst = selectedCustomInstaller, !inst.fileExists {
                    Label("IPSW file not found at its registered path.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        } header: { Text("IPSW source") }
          footer: { Text("Select a macOS version above. The IPSW download mode can be changed in Preferences.") }

        Section {
            LabeledContent("Tart name") {
                Text(tartName)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
        } footer: { Text("Names are generated automatically.") }
    }

    // MARK: Manual step 2 — Hardware

    @ViewBuilder private var manualHardwareStep: some View {
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
    }

    // MARK: Manual step 3 — Automation

    @ViewBuilder private var manualAutomationStep: some View {
        Section {
            Toggle("Automate Setup Assistant", isOn: $automateSetupAssistant)
        } header: { Text("Setup Assistant") }
          footer: {
            Text(automateSetupAssistant
                 ? "Oven will automate the macOS Setup Assistant using boot commands and then run the provisioners below."
                 : "The VM will start at the Setup Assistant. You can complete it manually and use the VM as-is.")
          }

        if automateSetupAssistant {
            // Boot command block picker
            let compatibleCmds = blockStore.bootCommands(for: osName.rawValue, version: resolvedOSVersion)
            Section {
                Picker("Boot command", selection: $bootCommandID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(compatibleCmds) { cmd in
                        VStack(alignment: .leading) {
                            Text(cmd.displayName)
                            if !cmd.osVersion.isEmpty {
                                Text(cmd.osName + " " + cmd.osVersion)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.tag(Optional(cmd.id))
                    }
                }
                if compatibleCmds.isEmpty {
                    Text("No boot command blocks for \(osName.rawValue) \(resolvedOSVersion). Add one in \(theme.recipes).")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: { Text("Boot command") }
              footer: { Text("Automates key-presses through the macOS Setup Assistant. Blocks are filtered to the selected OS version.") }

            // Credentials, provisioning, and MDM are only reachable when a boot
            // command is selected — without one the VM never reaches a logged-in
            // state so these provisioners would have nothing to connect to.
            if bootCommandID != nil {
                // Credentials
                Section("Credentials") {
                    LabeledContent("Username") {
                        TextField("", text: $manualUsername,
                                  prompt: Text("e.g. admin").foregroundStyle(.secondary))
                    }
                    LabeledContent("Password") {
                        SecureField("admin", text: $manualPassword)
                    }
                }

                // Provisioning options
                Section("Provisioning") {
                    Toggle("Passwordless sudo", isOn: provToggle(\.passwordlessSudo))
                    Toggle("Auto-login", isOn: provToggle(\.autoLogin))
                    Toggle("Disable sleep", isOn: provToggle(\.disableSleep))
                    Toggle("Disable screen lock", isOn: provToggle(\.disableScreenLock))
                    Toggle("Disable Spotlight indexing", isOn: provToggle(\.disableSpotlight))
                    Divider()
                    Toggle("Xcode Command Line Tools", isOn: provToggle(\.installCLITools))
                    Toggle("Homebrew", isOn: provToggle(\.installHomebrew))
                        .disabled(!provisioning.installCLITools)
                    Toggle("Xcode (via Homebrew cask)", isOn: provToggle(\.installXcode))
                        .disabled(!provisioning.installHomebrew)
                    Toggle("Safari automation", isOn: provToggle(\.safariAutomation))
                    Toggle("Tart guest agent", isOn: provToggle(\.tartGuestAgent))
                        .disabled(!provisioning.installHomebrew)
                }

                // MDM enrollment (last — runs after all other provisioning)
                if theme.mdmEnabled {
                    Section {
                        Picker("Enrollment profile", selection: $manualMDMProfileID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(mdmProfiles) { p in
                                Text(p.displayName).tag(Optional(p.id))
                            }
                        }
                        if let p = mdmProfiles.first(where: { $0.id == manualMDMProfileID }) {
                            if let sid = p.serverID,
                               let server = mdmServers.first(where: { $0.id == sid }) {
                                LabeledContent("Server") {
                                    Text(server.friendlyName).foregroundStyle(.secondary)
                                }
                            }
                            LabeledContent("Invitation ID") {
                                Text(p.invitationID.isEmpty ? "Not set" : p.invitationID)
                                    .foregroundStyle(p.invitationID.isEmpty ? .red : .secondary)
                            }
                            if p.invitationID.isEmpty {
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
                      footer: { Text("If selected, a .mobileconfig enrollment file will be generated and opened after provisioning completes.") }
                }
            } else {
                // Hint when no boot command is selected yet
                Section {
                    Label("Select a boot command above to enable credentials, provisioning, and MDM enrollment.",
                          systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func provToggle(_ kp: WritableKeyPath<ProvisioningOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { provisioning[keyPath: kp] },
            set: { provisioning[keyPath: kp] = $0; provisioning.enforceDependencies() }
        )
    }

    // MARK: Manual step 4 — Review

    @ViewBuilder private var manualReviewStep: some View {
        Section {
            LabeledContent("Tart name") {
                Text(tartName)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
            LabeledContent("OS") {
                let betaSuffix = isBetaOS ? (betaLabel.isEmpty ? " β" : " \(betaLabel)") : ""
                Text("\(osName.rawValue) \(resolvedOSVersion)\(betaSuffix)").foregroundStyle(.secondary)
            }
            LabeledContent("Hardware") {
                Text("\(cpuCount) CPU · \(memoryGB) GB RAM · \(diskGB) GB disk")
                    .foregroundStyle(.secondary)
            }
            if automateSetupAssistant && bootCommandID != nil {
                LabeledContent("Username") { Text(manualUsername).foregroundStyle(.secondary) }
                if let cmd = selectedBootCommandBlock {
                    LabeledContent("Boot command") { Text(cmd.displayName).foregroundStyle(.secondary) }
                }
                if let p = mdmProfiles.first(where: { $0.id == manualMDMProfileID }) {
                    LabeledContent("MDM enrollment") { Text(p.displayName).foregroundStyle(.secondary) }
                }
            }
        } header: { Text("Build summary") }

        Section {
            Toggle("Save to templates library", isOn: $saveToTemplates)
        } footer: { Text("Saves the generated HCL to your Packer templates folder so you can customise and reuse it.") }

        if !generatedHCL.isEmpty {
            Section("Generated HCL") {
                ScrollView {
                    Text(generatedHCL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 220)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Actions

    private func buildReviewHCL() {
        let config = buildManualConfig()
        generatedHCL = ManualBuildHCLGenerator.generate(
            config: config,
            bootCommand: selectedBootCommandBlock,
            resolvedIPSW: config.ipswSource.hclValue.isEmpty ? "<resolved-at-build-time>" : config.ipswSource.hclValue
        )
    }

    private func buildManualConfig() -> ManualBuildConfig {
        // Only carry credentials, provisioning, and MDM when a boot command is selected.
        // Without a boot command the VM never reaches a logged-in state.
        let hasBootCmd = bootCommandID != nil
        var config = ManualBuildConfig(
            displayName: displayName.isEmpty ? tartName : displayName,
            tartName: tartName,
            osName: osName.rawValue,
            osVersion: resolvedOSVersion,
            ipswSource: resolvedIPSWSource,
            cpuCount: cpuCount,
            memoryGB: memoryGB,
            diskGB: diskGB,
            automateSetupAssistant: automateSetupAssistant && hasBootCmd,
            bootCommandBlockID: bootCommandID,
            credentials: VMCredentials(username: manualUsername, password: manualPassword),
            provisioning: hasBootCmd ? provisioning : ProvisioningOptions()
        )
        config.mdmProfileID = hasBootCmd ? manualMDMProfileID : nil
        if ipswChoice == .customInstaller { config.customInstallerID = selectedCustomInstallerID }
        return config
    }

    private func createFromTemplate() {
        var vm = VirtualMachine(
            name: tartName,
            isBaseVM: true
        )
        vm.displayName         = displayName.isEmpty ? tartName : displayName
        vm.osName              = osName
        vm.osVersion           = resolvedOSVersion
        vm.isBetaOS            = isBetaOS
        vm.betaLabel           = betaLabel.trimmingCharacters(in: .whitespaces)
        vm.customOSMajorVersion = customOSMajorVersion.trimmingCharacters(in: .whitespaces)
        vm.customOSReleaseName  = customOSReleaseName.trimmingCharacters(in: .whitespaces)
        let releaseName = customOSReleaseName.trimmingCharacters(in: .whitespaces)
        vm.macOSVersion        = osName == .custom && !releaseName.isEmpty
            ? "\(releaseName) \(resolvedOSVersion)"
            : "macOS \(osName.rawValue) \(resolvedOSVersion)"
        vm.sshUsername         = tmplUsername
        vm.sshPassword         = tmplPassword.isEmpty ? nil : tmplPassword
        vm.cpuCount            = tmplCPU
        vm.memoryGB            = tmplMemory
        vm.diskGB              = tmplDisk
        vm.vmSource            = .local
        vm.buildStatus         = .notBuilt
        vm.mdmProfileID        = selectedMDMProfileID

        switch templateSource {
        case .library:
            vm.customTemplateID   = selectedTemplateID
            vm.customTemplatePath = nil
        case .customPath:
            vm.customTemplateID   = nil
            vm.customTemplatePath = externalTemplatePath.isEmpty ? nil : externalTemplatePath
        }
        vm.customVarsFileID = selectedVarsFileID

        if saveToTemplates {
            // For template path, saving to templates isn't relevant (already using one)
        }

        baseVMStore.add(vm)
        dismiss()
        Task { await baseVMStore.build(baseVM: vm) }
    }

    private func createManual() {
        let config = buildManualConfig()
        let effectivelyAutomates = config.automateSetupAssistant
        var vm = VirtualMachine(name: tartName, isBaseVM: true)
        vm.displayName          = config.displayName
        vm.osName               = osName
        vm.osVersion            = resolvedOSVersion
        vm.isBetaOS             = isBetaOS
        vm.betaLabel            = betaLabel.trimmingCharacters(in: .whitespaces)
        vm.customOSMajorVersion = customOSMajorVersion.trimmingCharacters(in: .whitespaces)
        vm.customOSReleaseName  = customOSReleaseName.trimmingCharacters(in: .whitespaces)
        let manualReleaseName = customOSReleaseName.trimmingCharacters(in: .whitespaces)
        vm.macOSVersion         = osName == .custom && !manualReleaseName.isEmpty
            ? "\(manualReleaseName) \(resolvedOSVersion)"
            : "macOS \(osName.rawValue) \(resolvedOSVersion)"
        vm.sshUsername  = effectivelyAutomates ? manualUsername : "admin"
        vm.sshPassword  = effectivelyAutomates ? (manualPassword.isEmpty ? nil : manualPassword) : nil
        vm.cpuCount     = cpuCount
        vm.memoryGB     = memoryGB
        vm.diskGB       = diskGB
        vm.vmSource     = .local
        vm.buildStatus  = .notBuilt
        vm.mdmProfileID = config.mdmProfileID

        switch config.ipswSource {
        case .filePath(let u): vm.ipswLocalPath = u.path
        case .url(let s):      vm.ipswRemoteURL = s
        case .auto:            break
        }

        let bootCmd = selectedBootCommandBlock

        if saveToTemplates {
            // Save the generated HCL as a new custom template
            Task {
                let fname = "\(tartName).pkr.hcl"
                _ = try? templateStore.create(
                    kind: .fullTemplate,
                    displayName: config.displayName,
                    description: "Generated by Oven for \(osName.rawValue) \(resolvedOSVersion)",
                    osName: osName.rawValue,
                    osVersion: resolvedOSVersion,
                    filename: fname,
                    starterContent: generatedHCL
                )
            }
        }

        vm.manualBuildConfig = config

        baseVMStore.add(vm)
        dismiss()
        Task { await baseVMStore.buildManual(baseVM: vm, config: config, bootCommandBlock: bootCmd) }
    }

    // MARK: - Helpers

    private func fetchLiveVersions() async {
        let fresh = await IPSWService.shared.isCacheFresh
        if fresh && !liveFirmwares.isEmpty { return }
        isFetchingVersions = true
        if let results = try? await IPSWService.shared.listFirmware() {
            liveFirmwares = results
        }
        isFetchingVersions = false
    }

    private func detectOS(from url: URL) {
        let filename = url.deletingPathExtension().lastPathComponent
        let parts = filename.components(separatedBy: CharacterSet(charactersIn: "-_"))
        for part in parts {
            let nums = part.components(separatedBy: ".")
            if nums.count >= 2, let major = Int(nums[0]), major >= 12 {
                switch major {
                case 26: osName = .tahoe
                case 15: osName = .sequoia
                case 14: osName = .sonoma
                case 13: osName = .ventura
                case 12: osName = .monterey
                default: osName = .custom
                }
                // Use custom sentinel if version isn't in the known list
                let known = versionList
                if known.contains(part) {
                    versionPickerSel = part
                    customVersionText = ""
                } else {
                    versionPickerSel = Self.customVersionSentinel
                    customVersionText = part
                }
                return
            }
        }
    }

    private func applyVersionFromInstaller(_ installer: Installer) {
        let m = installer.osMetadata
        let version = m.osVersion.isEmpty ? m.customMajorVersion : m.osVersion
        let list = versionList
        print("[NewBaseVM] applyVersionFromInstaller — version='\(version)' versionList.count=\(list.count) first='\(list.first ?? "nil")' contains=\(list.contains(version))")
        guard !version.isEmpty else {
            if let first = list.first {
                versionPickerSel = first
                print("[NewBaseVM] applyVersionFromInstaller — empty version, set first='\(first)'")
            }
            return
        }
        if list.contains(version) {
            versionPickerSel = version
            customVersionText = ""
        } else {
            versionPickerSel = Self.customVersionSentinel
            customVersionText = version
        }
    }

    private func loadMDMData() {
        let loaded = AppDatabase.shared.readOrDefault(.mdmProfiles, default: [MDMProfile]())
        if !loaded.isEmpty { mdmProfiles = loaded }
        let sloaded = AppDatabase.shared.readOrDefault(.mdmServers, default: [MDMServer]())
        if !sloaded.isEmpty { mdmServers = sloaded }
    }
}
