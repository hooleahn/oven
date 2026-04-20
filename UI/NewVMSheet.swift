import SwiftUI

// MARK: - NewVMSheet
// Extracted from VMListView to keep file size manageable.
// Creates a new VM cloned from a Base VM with standardised naming.

struct NewVMSheet: View {
    var preselectedBase: VirtualMachine? = nil   // pre-select a base VM when opening from Base VMs view

    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var theme: AppTheme
    @Environment(\.dismiss) var dismiss

    // Loaded from disk
    @State private var mdmServers:  [MDMServer]  = []
    @State private var mdmProfiles: [MDMProfile] = []

    // Form state
    @State private var selectedBaseVM: VirtualMachine? = nil
    @State private var selectedMDMProfileID: UUID? = nil
    @State private var displayName = ""
    @State private var description = ""
    @State private var tags: [String] = []
    @AppStorage("defaultCPUCount")       private var defaultCPU: Int = 4
    @AppStorage("defaultMemoryGB")       private var defaultMemory: Int = 8
    @AppStorage("defaultDiskGB")         private var defaultDisk: Int = 80
    @AppStorage("defaultPackerUsername") private var defaultPackerUsername: String = "baker"
    @State private var cpuCount = 4
    @State private var memoryGB = 8
    @State private var diskGB = 80
    @State private var sshUsername: String = "baker"
    @State private var sshPassword: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let cpuOptions  = [2, 4, 6, 8, 10, 12, 16]
    private let memOptions  = [4, 8, 12, 16, 24, 32, 48, 64]
    private let diskOptions = [40, 60, 80, 100, 120, 150, 200, 250, 500]

    var readyBaseVMs: [VirtualMachine] { baseVMStore.baseVMs.filter { $0.buildStatus == .ready } }

    var selectedMDMServer: MDMServer? {
        guard let pid = selectedMDMProfileID,
              let profile = mdmProfiles.first(where: { $0.id == pid }),
              let sid = profile.serverID,
              let server = mdmServers.first(where: { $0.id == sid })
        else { return nil }
        return server
    }

    // Standardised name: <osname>-<version>-<mdmserver|nomdm>-<shortid>
    var generatedName: String {
        guard let base = selectedBaseVM else { return "select-a-base-vm" }
        let shortID = String(UUID().uuidString.prefix(6).lowercased())
        if base.vmSource == .registry {
            // OCI base VMs: use the image short name (last path component before tag)
            let imagePart = base.name
                .components(separatedBy: "/").last?
                .components(separatedBy: ":").first?
                .replacingOccurrences(of: "macos-", with: "")
                ?? base.name
            let mdm = selectedMDMServer?.friendlyName
                .lowercased().replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                ?? "nomdm"
            return "\(imagePart)-\(mdm)-\(shortID)"
        }
        let os = base.osName.rawValue.lowercased()
        let ver = base.osVersion
        let mdm = selectedMDMServer?.friendlyName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            ?? "nomdm"
        return "\(os)-\(ver)-\(mdm)-\(shortID)"
    }


    var canCreate: Bool {
        selectedBaseVM != nil && !isCreating
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Virtual Machine").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Create") { Task { await createVM() } }
                    .buttonStyle(.borderedProminent).disabled(!canCreate)
            }
            .padding(16).background(.bar)
            Divider()

            if readyBaseVMs.isEmpty {
                // Guard: no ready base VMs
                ContentUnavailableView {
                    Label("No Base VMs Ready", systemImage: "shippingbox")
                } description: {
                    Text("Build or pull a Base VM first. Once it's ready, you can create VMs from it.")
                } actions: {
                    Button("Dismiss") { dismiss() }.buttonStyle(.bordered)
                }
                .frame(height: 300)
            } else {
                Form {
                    // Source
                    Section("Base VM") {
                        Picker("Source", selection: $selectedBaseVM) {
                            Text("Select a base VM…").tag(Optional<VirtualMachine>.none)
                            ForEach(readyBaseVMs) { base in
                                Text(base.vmSource == .registry
                                     ? base.name
                                     : "\(base.osName.rawValue) \(base.osVersion) — \(base.name)")
                                .tag(Optional(base))
                            }
                        }
                        if let base = selectedBaseVM {
                            LabeledContent("Source") {
                                Label(base.vmSource == .registry ? "Registry" : "Local",
                                      systemImage: base.vmSource == .registry ? "building.columns" : "shippingbox")
                                    .foregroundStyle(.secondary).font(.caption)
                            }
                            if base.vmSource == .local {
                                LabeledContent("Hardware") {
                                    Text("\(base.cpuCount) CPU · \(base.memoryGB) GB RAM · \(base.diskGB) GB disk")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Identity
                    Section {
                        LabeledContent("Generated name") {
                            Text(generatedName)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Display name") {
                            TextField("", text: $displayName, prompt: Text("Optional — shown in the VM list").foregroundColor(.secondary))
                        }
                        LabeledContent("Description") {
                            TextField("", text: $description, prompt: Text("Optional").foregroundColor(.secondary))
                        }
                        VStack(alignment: .leading) {
                            Text("Tags").font(.callout)
                            TagPickerField(
                                tags: $tags,
                                existingTags: Array(Set(vmStore.vms.flatMap { $0.tags })).sorted()
                            )
                        }
                    } header: { Text("Identity") }
                      footer: { Text("The VM name is generated from OS, version, MDM server, and a short unique ID.") }

                    // Hardware override
                    Section("SSH credentials") {
                    LabeledContent("Username") {
                        TextField("", text: $sshUsername,
                                  prompt: Text("e.g. baker").foregroundColor(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Password") {
                        SecureField("", text: $sshPassword,
                                    prompt: Text("optional, stored in Keychain").foregroundColor(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                }

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

                    // MDM
                    if theme.mdmEnabled {
                        Section("MDM enrollment") {
                            Picker("Profile", selection: $selectedMDMProfileID) {
                                Text("None").tag(Optional<UUID>.none)
                                ForEach(mdmProfiles) { p in
                                    Text(p.displayName).tag(Optional(p.id))
                                }
                            }
                            if let server = selectedMDMServer {
                                LabeledContent("Server") {
                                    Text(server.friendlyName).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Error
                    if let err = errorMessage {
                        Section {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red).font(.callout)
                        }
                    }
                }
                .formStyle(.grouped)

                if isCreating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Creating VM…").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(12).background(.bar)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: readyBaseVMs.isEmpty ? 360 : 560)
        .onAppear { loadMDMData() }
        .task {
            cpuCount = defaultCPU
            memoryGB = defaultMemory
            diskGB   = defaultDisk
            sshUsername = defaultPackerUsername
            sshPassword = KeychainService.retrieve(key: "defaults.packer.password") ?? ""
            await baseVMStore.syncOCI()
            initHardware()
        }
    }

    // MARK: Actions

    private func createVM() async {
        guard let base = selectedBaseVM else { return }
        isCreating = true; errorMessage = nil

        // Use generatedName which handles both local and OCI registry sources
        let name = generatedName

        do {
            try await vmStore.clone(
                source: base.name,
                newName: name,
                displayName: displayName.isEmpty ? nil : displayName,
                description: description,
                tags: tags,
                macOSVersion: "\(base.osName.rawValue) \(base.osVersion)",
                baseVMID: base.id,
                mdmProfileID: selectedMDMProfileID,
                cpuCount: cpuCount,
                memoryGB: memoryGB,
                diskGB: diskGB,
                mdmServerID: selectedMDMServer?.id,
                sshUsername: sshUsername.isEmpty ? base.sshUsername : sshUsername
            )
            // Store password in Keychain on the newly created VM
            if let vm = vmStore.vms.first(where: { $0.name == name }) {
                vmStore.update(id: vm.id) { v in
                    v.sshPassword = sshPassword.isEmpty ? nil : sshPassword
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }

    private func initHardware() {
        let base = preselectedBase ?? readyBaseVMs.first
        if let base {
            selectedBaseVM = base
            // For OCI base VMs, defaults are generic (4/8/80) — keep form defaults
            // For locally built base VMs, mirror the base hardware
            if base.vmSource == .local {
                cpuCount = base.cpuCount
                memoryGB = base.memoryGB
                diskGB = base.diskGB
            }
        }
    }

    private func loadMDMData() {
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
