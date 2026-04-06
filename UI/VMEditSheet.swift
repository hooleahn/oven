import SwiftUI

// MARK: - VMEditSheet

struct VMEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var tagStore: TagStore

    let vm: VirtualMachine

    @State private var displayName: String
    @State private var tartName: String
    @State private var tartNameError: String?
    @State private var description: String
    @State private var tags: [String]
    @State private var sharedFolders: [VirtualMachine.SharedFolder]
    @State private var showFolderPicker = false
    @State private var editingFolder: VirtualMachine.SharedFolder? = nil
    // Hardware — applied via tart set on save
    @State private var cpuCount: Int
    @State private var memoryGB: Int
    @State private var displayResolution: String
    @State private var isSavingHardware = false
    @State private var hardwareError: String?
    @State private var sshUsername: String = ""
    @State private var sshPassword: String = ""
    @State private var isBaseVM: Bool = false
    @State private var osName: MacOSRelease.Name
    @State private var osVersion: String
    @State private var serialNumber: String
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false

    private var versionList: [String] {
        sofaVersions.isEmpty ? osName.fallbackVersions : sofaVersions
    }

    private let displayPresets = [
        "1920x1080", "2560x1440", "2560x1600", "3840x2160",
        "1280x800",  "1440x900"
    ]

    init(vm: VirtualMachine) {
        self.vm = vm
        _displayName       = State(initialValue: vm.displayName == vm.name ? "" : vm.displayName)
        _tartName          = State(initialValue: vm.name)
        _tartNameError     = State(initialValue: nil)
        _description       = State(initialValue: vm.description)
        _tags              = State(initialValue: vm.tags)
        _sshUsername       = State(initialValue: vm.sshUsername)
        _isBaseVM          = State(initialValue: vm.isBaseVM)
        _osName            = State(initialValue: vm.osName)
        _osVersion         = State(initialValue: vm.osVersion)
        _serialNumber      = State(initialValue: vm.serialNumber)
        _sharedFolders     = State(initialValue: vm.sharedFolders)
        _cpuCount          = State(initialValue: vm.cpuCount)
        _memoryGB          = State(initialValue: vm.memoryGB)
        _displayResolution = State(initialValue: "1920x1080")
    }

    private var allKnownTags: [String] {
        let fromVMs = vmStore.vms.flatMap { $0.tags }
        let fromStore = tagStore.managedTags
        return Array(Set(fromVMs + fromStore)).sorted()
    }

    /// Max vCPUs to offer: host core count minus 2 for the host OS, minimum 1.
    private var maxCPU: Int {
        max(1, ProcessInfo.processInfo.processorCount - 2)
    }

    /// Max RAM to offer: half of host physical RAM in GB, rounded to nearest 2 GB,
    /// capped at 192 GB. Leaves the other half for the host OS.
    private var maxMemoryGB: Int {
        let hostGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let half = (hostGB / 2) & ~1   // round down to even number
        return max(2, min(half, 192))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit \"\(vm.name)\"").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Group {
                    if isSavingHardware {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { save() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty
                                      && displayName != "")
                    }
                }
            }
            .padding(16).background(.bar)
            Divider()

            Form {
                Section("Identity") {
                    LabeledContent("Display name") {
                        TextField("", text: $displayName, prompt: Text(vm.name).foregroundColor(.secondary))
                    }
                    LabeledContent("Tart name") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("", text: $tartName)
                                .font(.system(.body, design: .monospaced))
                                .onChange(of: tartName) { _, v in
                                    let clean = v.lowercased()
                                        .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                                    tartNameError = clean.isEmpty ? "Name cannot be empty"
                                        : (clean == vm.name ? nil
                                        : (vmStore.vms.contains(where: { $0.name == clean && $0.id != vm.id })
                                            ? "Name already in use" : nil))
                                    if clean != v { tartName = clean }
                                }
                            if let err = tartNameError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    LabeledContent("Description") {
                        TextField("", text: $description,
                                  prompt: Text("What is this VM for?").foregroundColor(.secondary),
                                  axis: .vertical)
                            .lineLimit(3...6)
                    }
                }

                Section("Tags") {
                    TagPickerField(tags: $tags, existingTags: allKnownTags)
                }

                Section {
                    if vm.isOCIBased {
                        LabeledContent("Category") {
                            Text("Base VM (OCI — locked)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle("Use as Base VM", isOn: $isBaseVM)
                    }
                } header: { Text("Category") }
                  footer: { Text(isBaseVM
                    ? "Base VMs can be cloned but not started. Toggle off to use this as a working VM."
                    : "Working VMs can be started and cloned. Toggle on to treat this as a Base VM.") }

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
                            Text("Unknown").tag("Unknown")
                            ForEach(versionList, id: \.self) { v in Text(v).tag(v) }
                        }
                        if isFetchingVersions {
                            ProgressView().controlSize(.mini).padding(.leading, 4)
                        }
                    }
                    LabeledContent("Serial Number") {
                        TextField("", text: $serialNumber, prompt: Text(vm.serialNumber).foregroundColor(.secondary))
                    }
                }

                Section("Default and SSH credentials") {
                    LabeledContent("Username") {
                        TextField("", text: $sshUsername,
                                  prompt: Text("e.g. baker").foregroundColor(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Password") {
                        SecureField("", text: $sshPassword,
                                    prompt: Text("stored in Keychain").foregroundColor(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Stepper("\(cpuCount) vCPU\(cpuCount == 1 ? "" : "s")", value: $cpuCount, in: 1...maxCPU)
                    Stepper("\(memoryGB) GB RAM", value: $memoryGB, in: 2...maxMemoryGB, step: 2)
                    LabeledContent("Display") {
                        HStack(spacing: 6) {
                            Picker("", selection: $displayResolution) {
                                ForEach(displayPresets, id: \.self) { Text($0).tag($0) }
                                if !displayPresets.contains(displayResolution) {
                                    Text(displayResolution).tag(displayResolution)
                                }
                            }
                            .labelsHidden().frame(maxWidth: 160)
                        }
                    }
                    if let err = hardwareError {
                        Label(err, systemImage: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                } header: { Text("Hardware") }
                  footer: {
                    Text("Changes apply via `tart set` when you save. VM must be stopped. Host limits: \(maxCPU) vCPU, \(maxMemoryGB) GB RAM.")
                  }

                Section {
                    ForEach(sharedFolders) { folder in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name).fontWeight(.medium)
                                Text(folder.hostPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if folder.readOnly {
                                Text("read-only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Button {
                                sharedFolders.removeAll { $0.id == folder.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Add shared folder", systemImage: "plus.circle")
                    }
                } header: { Text("Shared folders") }
                  footer: { Text("Folders are mounted read-only inside the VM by default. Pass via `tart run --dir name:path[:options]`.") }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 480)
        .task { await loadVersions(for: osName) }
        .onAppear {
            // Clamp stored values to current host limits in case hardware changed
            cpuCount  = min(cpuCount, maxCPU)
            memoryGB  = min(memoryGB, maxMemoryGB)
            // Load password from keychain
            sshPassword = vm.sshPassword ?? ""
        }
        .sheet(isPresented: $showFolderPicker) {
            SharedFolderSheet { folder in
                sharedFolders.append(folder)
            }
        }
    }

    private func loadVersions(for release: MacOSRelease.Name) async {
        isFetchingVersions = true
        sofaVersions = await SOFAService.shared.versions(for: release)
        isFetchingVersions = false
    }

    private func save() {
        vmStore.update(id: vm.id) { v in
            let trimmed = displayName.trimmingCharacters(in: .whitespaces)
            v.displayName   = trimmed.isEmpty ? (tartName.isEmpty ? vm.name : tartName) : trimmed
            v.description   = description
            v.tags          = tags
            v.sshUsername   = sshUsername
            v.sharedFolders = sharedFolders
            v.cpuCount      = cpuCount
            v.memoryGB      = memoryGB
            v.osName        = osName
            v.osVersion     = osVersion
            v.serialNumber  = serialNumber
            v.sshPassword   = sshPassword.isEmpty ? nil : sshPassword
            if !v.isOCIBased { v.isBaseVM = isBaseVM }
        }
        // Rename tart VM if name changed
        if tartName != vm.name && !tartName.isEmpty && tartNameError == nil {
            Task {
                do {
                    try await vmStore.rename(vm: vm, to: tartName)
                } catch {
                    // rename failed — not fatal, metadata already saved
                    AppLogger.shared.error("Rename failed: \(error.localizedDescription)", source: "VMEditSheet")
                }
            }
        }
        // Apply hardware changes via tart set if anything changed
        let hardwareChanged = cpuCount != vm.cpuCount || memoryGB != vm.memoryGB
            || displayResolution != "1920x1080"

        if hardwareChanged {
            Task { await applyHardware() }
        } else {
            dismiss()
        }
    }

    @MainActor private func applyHardware() async {
        isSavingHardware = true
        hardwareError = nil
        let tartPath = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        guard FileManager.default.fileExists(atPath: tartPath) else {
            hardwareError = "tart not found"; isSavingHardware = false; return
        }
        let svc = TartService(runner: ProcessRunner(), tartPath: tartPath)
        do {
            try await svc.set(
                name: vm.name,
                cpu: cpuCount != vm.cpuCount ? cpuCount : nil,
                memoryGB: memoryGB != vm.memoryGB ? memoryGB : nil,
                display: displayResolution
            )
            AppLogger.shared.success(
                "Hardware updated: \(vm.name) — \(cpuCount) vCPU, \(memoryGB) GB, \(displayResolution)",
                source: "VMEditSheet")
            dismiss()
        } catch {
            hardwareError = error.localizedDescription
        }
        isSavingHardware = false
    }
}

// MARK: - SharedFolderSheet

struct SharedFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (VirtualMachine.SharedFolder) -> Void

    @State private var name = ""
    @State private var hostPath = ""
    @State private var readOnly = true
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Shared Folder").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Add") {
                    onAdd(VirtualMachine.SharedFolder(name: name, hostPath: hostPath, readOnly: readOnly))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || hostPath.isEmpty)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Mount name") {
                    TextField("", text: $name, prompt: Text("e.g. projects").foregroundColor(.secondary))
                }
                Section("Host path") {
                    HStack {
                        TextField("", text: $hostPath, prompt: Text("/Users/you/Projects").foregroundColor(.secondary))
                        Button("Browse…") { showPicker = true }
                            .controlSize(.small)
                    }
                }
                Section {
                    Toggle("Read-only", isOn: $readOnly)
                } footer: {
                    Text("Read-only prevents the VM from writing to the host folder.")
                }
                if !name.isEmpty && !hostPath.isEmpty {
                    Section("Preview") {
                        Text("--dir \(name):\(hostPath)\(readOnly ? ":ro" : "")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 400, idealWidth: 440, minHeight: 320)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if let url = try? result.get() { hostPath = url.path }
        }
    }
}
