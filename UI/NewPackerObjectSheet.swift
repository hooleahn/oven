import SwiftUI
import UniformTypeIdentifiers

// MARK: - NewPackerObjectSheet
// Unified creation sheet: lets the user pick Full Template, Template Variables,
// Building Block, or Boot Command Block before filling in details.

struct NewPackerObjectSheet: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    enum ObjectKind: String, CaseIterable, Identifiable {
        case fullTemplate = "Full Template"
        case varsFile     = "Template Variables"
        case block        = "Building Block"
        case bootCommand  = "Boot Command Block"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .fullTemplate: return "doc.text"
            case .varsFile:     return "slider.horizontal.3"
            case .block:        return "puzzlepiece"
            case .bootCommand:  return "command"
            }
        }

        var description: String {
            switch self {
            case .fullTemplate:
                return "A complete .pkr.hcl Packer build definition. Drives the full VM build pipeline."
            case .varsFile:
                return "A .pkrvars.hcl file that overrides variables in a Full Template — hardware, names, and more. Avoid storing passwords here; use Keychain credentials instead."
            case .block:
                return "A reusable HCL provisioner snippet to copy-paste into Full Templates. Building Blocks are not built directly."
            case .bootCommand:
                return "A sequence of key-press commands that automate the macOS Setup Assistant. Used in the manual Base VM build path to bring the VM to a logged-in state."
            }
        }
    }

    let onCreatedTemplate: (UUID) -> Void
    let onCreatedBlock: (BuildingBlock) -> Void
    let onCreatedBootCommand: (BootCommandBlock) -> Void

    @State private var selectedKind: ObjectKind = .fullTemplate
    @State private var page: Page = .typePicker

    enum Page { case typePicker, details }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch page {
            case .typePicker: typePickerPage
            case .details:    detailsPage
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if page == .details {
                Button {
                    page = .typePicker
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            Text(page == .typePicker ? "New Packer Object" : "New \(selectedKind.rawValue)")
                .bold()
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
        }
        .padding(16).background(.bar)
    }

    // MARK: - Type picker page

    private var typePickerPage: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(ObjectKind.allCases) { kind in
                        Button {
                            selectedKind = kind
                            page = .details
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: kind.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(kind.rawValue).bold()
                                    Text(kind.description)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Details page (kind-specific)

    @ViewBuilder
    private var detailsPage: some View {
        switch selectedKind {
        case .fullTemplate:
            FullTemplateCreationForm(onCreated: { id in onCreatedTemplate(id); dismiss() })
                .environment(theme)
        case .varsFile:
            VarsFileCreationForm(onCreated: { id in onCreatedTemplate(id); dismiss() })
        case .block:
            BuildingBlockCreationForm { block in onCreatedBlock(block); dismiss() }
        case .bootCommand:
            BootCommandCreationForm { cmd in onCreatedBootCommand(cmd); dismiss() }
        }
    }
}

// MARK: - Shared footer helper

private struct CreationFooter: View {
    let isCreateDisabled: Bool
    let onImport: () -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack {
            Button("Import from File", action: onImport)
                .buttonStyle(.bordered)
            Spacer()
            Button("Create", action: onCreate)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreateDisabled)
        }
        .padding(16)
        .background(.bar)
    }
}

// MARK: - Full Template Creation Form

private struct FullTemplateCreationForm: View {
    @Environment(AppTheme.self) private var theme
    @Environment(PackerTemplateStore.self) private var templateStore

    let onCreated: (UUID) -> Void

    @State private var displayName = ""
    @State private var description = ""
    @State private var osName: MacOSRelease.Name = .sequoia
    @State private var versionPickerSel = ""
    @State private var customVersionText = ""
    @State private var customOSMajorVersion = ""
    @State private var customOSReleaseName = ""
    @State private var liveFirmwares: [MistFirmwareInfo] = []
    @State private var isFetchingVersions = false
    @State private var createError: String?
    @State private var isImporting = false
    @State private var pendingImportURL: URL? = nil

    private static let customVersionSentinel = "__custom__"

    private var versionList: [String] {
        let major = osName.majorVersion
        let live = liveFirmwares.filter { $0.version.hasPrefix(String(major)) }.map(\.version)
        if live.isEmpty { return osName.fallbackVersions }
        var seen = Set<String>()
        return live.filter { seen.insert($0).inserted }
    }

    private var resolvedOSVersion: String {
        versionPickerSel == Self.customVersionSentinel ? customVersionText : versionPickerSel
    }

    private var filename: String {
        let base = displayName.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return base.isEmpty ? "template.pkr.hcl" : "\(base).pkr.hcl"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Display Name") {
                    TextField("", text: $displayName,
                              prompt: Text("e.g. Sequoia Vanilla").foregroundStyle(.tertiary))
                }
                LabeledContent("Description") {
                    TextField("", text: $description, axis: .vertical).lineLimit(2...4)
                }
            } header: { Text("Identity") }

            Section {
                Picker("OS", selection: $osName) {
                    ForEach(MacOSRelease.Name.allCases.filter { $0 != .unknown && $0 != .any }, id: \.self) {
                        Text($0.displayLabel).tag($0)
                    }
                }
                .onChange(of: osName) { _, _ in
                    versionPickerSel = ""; customVersionText = ""
                    customOSMajorVersion = ""; customOSReleaseName = ""
                    Task { await fetchVersions() }
                }
                if osName == .custom {
                    LabeledContent("Major version") {
                        TextField("e.g. 27", text: $customOSMajorVersion)
                            .multilineTextAlignment(.trailing)
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
                        if sel != Self.customVersionSentinel { customVersionText = "" }
                    }
                    if isFetchingVersions { ProgressView().controlSize(.mini) }
                }
                if versionPickerSel == Self.customVersionSentinel {
                    LabeledContent("Custom version") {
                        TextField("e.g. 26.5", text: $customVersionText)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } header: { Text("Target OS") }
              footer: {
                  VStack(alignment: .leading, spacing: 4) {
                      Text("Will be created as: \(filename)")
                      if let err = createError { Text(err).foregroundStyle(.red) }
                  }
              }
        }
        .formStyle(.grouped)

        Divider()
        CreationFooter(
            isCreateDisabled: displayName.trimmingCharacters(in: .whitespaces).isEmpty || resolvedOSVersion.isEmpty,
            onImport: { isImporting = true },
            onCreate: create
        )
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.text, .data]) { result in
            if case .success(let url) = result { pendingImportURL = url }
        }
        .onChange(of: pendingImportURL) { _, url in
            guard let url else { return }
            pendingImportURL = nil
            handleImport(url: url)
        }
        .task { await fetchVersions() }
    }

    private func fetchVersions() async {
        let mistPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/mist-cli").path
        guard FileManager.default.fileExists(atPath: mistPath) else { return }
        isFetchingVersions = true
        let svc = MistService(runner: ProcessRunner(), mistPath: mistPath,
                              ipswRoot: AppSettings.load().ipswStorageRoot,
                              includeBetas: AppSettings.load().mistIncludeBetas)
        if let results = try? await svc.listFirmware() { liveFirmwares = results }
        isFetchingVersions = false
    }

    private func create() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let version = resolvedOSVersion
        guard !name.isEmpty, !version.isEmpty else { return }
        doCreate(content: starterTemplate(osName: osName, osVersion: version))
    }

    private func handleImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            displayName = url.deletingPathExtension().lastPathComponent
        }
        doCreate(content: content)
    }

    private func doCreate(content: String) {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let id = try templateStore.create(
                kind: .fullTemplate,
                displayName: name,
                description: description,
                osName: osName.rawValue,
                osVersion: resolvedOSVersion,
                filename: filename,
                starterContent: content
            )
            onCreated(id)
        } catch {
            createError = error.localizedDescription
        }
    }

    private func starterTemplate(osName: MacOSRelease.Name, osVersion: String) -> String {
        """
packer {
  required_plugins {
    tart = {
      version = ">= 1.20.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "vm_name"          { type = string  default = "my-base-vm" }
variable "ipsw_url"         { type = string  default = "latest" }
variable "account_userName" { type = string  default = "baker" }
variable "account_password" { type = string  default = env("OVEN_VM_PASSWORD")  sensitive = true }

source "tart-cli" "tart" {
  from_ipsw    = var.ipsw_url
  vm_name      = var.vm_name
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 80
  ssh_username = var.account_userName
  ssh_password = var.account_password
  ssh_timeout  = "180s"
  run_extra_args    = ["--no-audio"]
  create_grace_time = "30s"
  recovery_partition = "keep"
}

build {
  sources = ["source.tart-cli.tart"]
  provisioner "shell" {
    inline = ["echo 'Base build complete'"]
  }
}
"""
    }
}

// MARK: - Vars File Creation Form

private struct VarsFileCreationForm: View {
    @Environment(PackerTemplateStore.self) private var templateStore

    let onCreated: (UUID) -> Void

    @State private var displayName = ""
    @State private var description = ""
    @State private var createError: String?
    @State private var isImporting = false
    @State private var pendingImportURL: URL? = nil

    private var filename: String {
        let base = displayName.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return base.isEmpty ? "variables.pkrvars.hcl" : "\(base).pkrvars.hcl"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Display Name") {
                    TextField("", text: $displayName,
                              prompt: Text("e.g. Dev Hardware Override").foregroundStyle(.tertiary))
                }
                LabeledContent("Description") {
                    TextField("", text: $description, axis: .vertical).lineLimit(2...4)
                }
            } header: { Text("Identity") }
              footer: {
                  VStack(alignment: .leading, spacing: 4) {
                      Label("Avoid storing passwords in vars files. Use Keychain credentials in the Build sheet instead.",
                            systemImage: "lock.shield")
                          .foregroundStyle(.orange)
                      Text("Will be created as: \(filename)")
                      if let err = createError { Text(err).foregroundStyle(.red) }
                  }
              }
        }
        .formStyle(.grouped)

        Divider()
        CreationFooter(
            isCreateDisabled: displayName.trimmingCharacters(in: .whitespaces).isEmpty,
            onImport: { isImporting = true },
            onCreate: create
        )
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.text, .data]) { result in
            if case .success(let url) = result { pendingImportURL = url }
        }
        .onChange(of: pendingImportURL) { _, url in
            guard let url else { return }
            pendingImportURL = nil
            handleImport(url: url)
        }
    }

    private func create() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let starter = """
# Template Variables File
# Override variable defaults from a Full Template.
# Run: packer build -var-file=\(filename) your-template.pkr.hcl
#
# WARNING: Do not store passwords here. Use Keychain credentials in the Oven Build sheet.

vm_name          = "my-vm"
# ipsw_url       = "latest"
# account_userName = "baker"
# cpu_count      = 4
# memory_gb      = 8
# disk_size_gb   = 80
"""
        doCreate(content: starter)
    }

    private func handleImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            displayName = url.deletingPathExtension().lastPathComponent
        }
        doCreate(content: content)
    }

    private func doCreate(content: String) {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let id = try templateStore.create(
                kind: .varsFile,
                displayName: name,
                description: description,
                osName: "",
                osVersion: "",
                filename: filename,
                starterContent: content
            )
            onCreated(id)
        } catch {
            createError = error.localizedDescription
        }
    }
}

// MARK: - Building Block Creation Form

private struct BuildingBlockCreationForm: View {
    let onCreated: (BuildingBlock) -> Void

    @State private var displayName = ""
    @State private var description = ""
    @State private var provisioner: BuildingBlock.ProvisionerType = .shell
    @State private var isImporting = false
    @State private var pendingImportURL: URL? = nil

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Name") {
                    TextField("", text: $displayName,
                              prompt: Text("e.g. Install Rosetta").foregroundStyle(.tertiary))
                }
                LabeledContent("Description") {
                    TextField("", text: $description, axis: .vertical).lineLimit(2...5)
                }
                Picker("Provisioner type", selection: $provisioner) {
                    ForEach(BuildingBlock.ProvisionerType.allCases, id: \.self) {
                        Label($0.label, systemImage: $0.systemImage).tag($0)
                    }
                }
            }
        }
        .formStyle(.grouped)

        Divider()
        CreationFooter(
            isCreateDisabled: displayName.trimmingCharacters(in: .whitespaces).isEmpty,
            onImport: { isImporting = true },
            onCreate: create
        )
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.text, .data]) { result in
            if case .success(let url) = result { pendingImportURL = url }
        }
        .onChange(of: pendingImportURL) { _, url in
            guard let url else { return }
            pendingImportURL = nil
            handleImport(url: url)
        }
    }

    private func create() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onCreated(BuildingBlock(
            displayName: name,
            blockDescription: description,
            provisioner: provisioner,
            hclContent: """
  provisioner "shell" {
    inline = [
      "echo 'Hello from Packer'"
    ]
  }
"""
        ))
    }

    private func handleImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            displayName = url.deletingPathExtension().lastPathComponent
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onCreated(BuildingBlock(
            displayName: name,
            blockDescription: description,
            provisioner: provisioner,
            hclContent: content
        ))
    }
}

// MARK: - Boot Command Creation Form

private struct BootCommandCreationForm: View {
    let onCreated: (BootCommandBlock) -> Void

    @State private var displayName = ""
    @State private var description = ""
    @State private var osName: MacOSRelease.Name = .sequoia
    @State private var osVersion = ""
    @State private var isImporting = false
    @State private var pendingImportURL: URL? = nil

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Name") {
                    TextField("", text: $displayName,
                              prompt: Text("e.g. macOS 15 Setup Assistant").foregroundStyle(.tertiary))
                }
                LabeledContent("Description") {
                    TextField("", text: $description, axis: .vertical).lineLimit(2...5)
                }
            }
            Section("OS Compatibility") {
                Picker("OS", selection: $osName) {
                    ForEach(MacOSRelease.Name.allCases, id: \.self) {
                        Text($0.displayLabel).tag($0)
                    }
                }
                LabeledContent("Version") {
                    TextField("", text: $osVersion,
                              prompt: Text("Leave empty to match any version").foregroundStyle(.tertiary))
                }
            }
        }
        .formStyle(.grouped)

        Divider()
        CreationFooter(
            isCreateDisabled: displayName.trimmingCharacters(in: .whitespaces).isEmpty,
            onImport: { isImporting = true },
            onCreate: create
        )
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.text, .data]) { result in
            if case .success(let url) = result { pendingImportURL = url }
        }
        .onChange(of: pendingImportURL) { _, url in
            guard let url else { return }
            pendingImportURL = nil
            handleImport(url: url)
        }
    }

    private func create() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onCreated(BootCommandBlock(
            displayName: name,
            blockDescription: description,
            commandLines: ["\"<wait60s><spacebar>\""],
            osName: osName.rawValue,
            osVersion: osVersion.trimmingCharacters(in: .whitespaces)
        ))
    }

    private func handleImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        if displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            displayName = url.deletingPathExtension().lastPathComponent
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let lines = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        onCreated(BootCommandBlock(
            displayName: name,
            blockDescription: description,
            commandLines: lines,
            osName: osName.rawValue,
            osVersion: osVersion.trimmingCharacters(in: .whitespaces)
        ))
    }
}
