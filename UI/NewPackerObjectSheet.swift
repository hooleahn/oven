import SwiftUI

// MARK: - NewPackerObjectSheet
// Unified creation sheet: lets the user pick Full Template, Template Variables,
// or Building Block before filling in details.

struct NewPackerObjectSheet: View {
    @EnvironmentObject var theme: AppTheme
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
                .environmentObject(theme)
        case .varsFile:
            VarsFileCreationForm(onCreated: { id in onCreatedTemplate(id); dismiss() })
        case .block:
            BuildingBlockEditSheet(block: nil) { block in onCreatedBlock(block); dismiss() }
        case .bootCommand:
            BootCommandEditSheet(cmd: nil) { cmd in onCreatedBootCommand(cmd); dismiss() }
        }
    }
}

// MARK: - Full Template Creation Form

private struct FullTemplateCreationForm: View {
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var templateStore: PackerTemplateStore

    let onCreated: (UUID) -> Void

    @State private var displayName = ""
    @State private var description = ""
    @State private var osName: MacOSRelease.Name = .sequoia
    @State private var osVersion = ""
    @State private var liveFirmwares: [MistFirmwareInfo] = []
    @State private var isFetchingVersions = false
    @State private var createError: String?

    private var versionList: [String] {
        let major = osName.majorVersion
        let live = liveFirmwares.filter { $0.version.hasPrefix(String(major)) }.map(\.version)
        if live.isEmpty { return osName.fallbackVersions }
        var seen = Set<String>()
        return live.filter { seen.insert($0).inserted }
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
                    ForEach(MacOSRelease.Name.allCases, id: \.self) {
                        Text($0.displayLabel).tag($0)
                    }
                }
                HStack {
                    Picker("Version", selection: $osVersion) {
                        Text("Select a version…").tag("")
                        ForEach(versionList, id: \.self) { Text($0).tag($0) }
                    }
                    if isFetchingVersions { ProgressView().controlSize(.mini) }
                }
                .onChange(of: osName) { _, _ in osVersion = ""; Task { await fetchVersions() } }
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
        HStack {
            Spacer()
            Button("Create") { create() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || osVersion.isEmpty)
                .padding(16)
        }
        .background(.bar)
        .task { await fetchVersions() }
    }

    private func fetchVersions() async {
        let mistPath = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/mist-cli").path
        guard FileManager.default.fileExists(atPath: mistPath) else { return }
        isFetchingVersions = true
        let svc = MistService(runner: ProcessRunner(), mistPath: mistPath,
                              ipswRoot: AppSettings.load().ipswStorageRoot)
        if let results = try? await svc.listFirmware() { liveFirmwares = results }
        isFetchingVersions = false
    }

    private func create() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !osVersion.isEmpty else { return }
        let starter = starterTemplate(osName: osName, osVersion: osVersion)
        do {
            let id = try templateStore.create(
                kind: .fullTemplate,
                displayName: name,
                description: description,
                osName: osName.rawValue,
                osVersion: osVersion,
                filename: filename,
                starterContent: starter
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
    @EnvironmentObject var templateStore: PackerTemplateStore

    let onCreated: (UUID) -> Void

    @State private var displayName = ""
    @State private var description = ""
    @State private var createError: String?

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
        HStack {
            Spacer()
            Button("Create") { create() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(16)
        }
        .background(.bar)
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
        do {
            let id = try templateStore.create(
                kind: .varsFile,
                displayName: name,
                description: description,
                osName: "",
                osVersion: "",
                filename: filename,
                starterContent: starter
            )
            onCreated(id)
        } catch {
            createError = error.localizedDescription
        }
    }
}
