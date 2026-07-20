import SwiftUI
import LocalAuthentication

// MARK: - VMEditSheet

struct VMEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VMStore.self) private var vmStore
    @Environment(TagStore.self) private var tagStore
    @Environment(MDMServerStore.self) private var serverStore
    @Environment(AppTheme.self) private var theme

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
    @State private var isPasswordRevealed = false
    @State private var isAuthenticatingPassword = false
    @State private var supportsGuestAgent: Bool = false
    @State private var isBaseVM: Bool = false
    @State private var osName: MacOSRelease.Name
    @State private var versionPickerSel: String       // picker binding; "__custom__" means custom
    @State private var customVersionText: String      // text when Custom version selected
    @State private var isBetaOS: Bool
    @State private var betaLabel: String
    @State private var customOSMajorVersion: String
    @State private var customOSReleaseName: String
    @State private var majorVersionError: String? = nil
    @State private var customVersionError: String? = nil

    private static let ipswVersionRegex = /^\d+(\.\d+)*$/
    @State private var serialNumber: String
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false
    @State private var mdmServerID: UUID?

    // Schedule
    @State private var scheduleEnabled: Bool
    @State private var scheduleStartTimeEnabled: Bool
    @State private var scheduleStartTime: Date
    @State private var scheduleStartDays: Set<Int>
    @State private var scheduleStopTimeEnabled: Bool
    @State private var scheduleStopTime: Date
    @State private var scheduleStopDays: Set<Int>
    @State private var scheduleStartOnAppLaunch: Bool
    @State private var scheduleLaunchMode: VMScheduleLaunchMode
    @State private var scheduleForceVMLaunch: Bool

    private static let customVersionSentinel = "__custom__"

    private var versionList: [String] {
        sofaVersions.isEmpty ? osName.fallbackVersions : sofaVersions
    }

    private var resolvedOSVersion: String {
        versionPickerSel == Self.customVersionSentinel ? customVersionText : versionPickerSel
    }

    private let displayPresets = [
        "1920x1080", "2560x1440", "2560x1600", "3840x2160",
        "1280x800",  "1440x900"
    ]

    init(vm: VirtualMachine) {
        self.vm = vm
        _displayName          = State(initialValue: vm.displayName == vm.name ? "" : vm.displayName)
        _tartName             = State(initialValue: vm.name)
        _tartNameError        = State(initialValue: nil)
        _description          = State(initialValue: vm.description)
        _tags                 = State(initialValue: vm.tags)
        _sshUsername          = State(initialValue: vm.sshUsername)
        _supportsGuestAgent   = State(initialValue: vm.supportsGuestAgent)
        _isBaseVM             = State(initialValue: vm.isBaseVM)
        _osName               = State(initialValue: vm.osName)
        _isBetaOS             = State(initialValue: vm.isBetaOS)
        _betaLabel            = State(initialValue: vm.betaLabel)
        _customOSMajorVersion = State(initialValue: vm.customOSMajorVersion)
        _customOSReleaseName  = State(initialValue: vm.customOSReleaseName)
        _serialNumber         = State(initialValue: vm.serialNumber)
        _mdmServerID          = State(initialValue: vm.mdmServerID)
        _sharedFolders        = State(initialValue: vm.sharedFolders)
        _cpuCount             = State(initialValue: vm.cpuCount)
        _memoryGB             = State(initialValue: vm.memoryGB)
        _displayResolution    = State(initialValue: "1920x1080")
        // Determine if the stored version is custom (not in the static fallback list)
        let fallback = vm.osName.fallbackVersions
        let isCustom = !vm.osVersion.isEmpty && !fallback.contains(vm.osVersion)
        _versionPickerSel  = State(initialValue: isCustom ? "__custom__" : vm.osVersion)
        _customVersionText = State(initialValue: isCustom ? vm.osVersion : "")

        // Schedule
        _scheduleEnabled          = State(initialValue: vm.scheduleEnabled)
        _scheduleStartTimeEnabled = State(initialValue: vm.scheduleStartTime != nil)
        _scheduleStartTime        = State(initialValue: vm.scheduleStartTime ?? VMEditSheet.defaultTime(hour: 9))
        _scheduleStartDays        = State(initialValue: vm.scheduleStartDays)
        _scheduleStopTimeEnabled  = State(initialValue: vm.scheduleStopTime != nil)
        _scheduleStopTime         = State(initialValue: vm.scheduleStopTime ?? VMEditSheet.defaultTime(hour: 18))
        _scheduleStopDays         = State(initialValue: vm.scheduleStopDays)
        _scheduleStartOnAppLaunch = State(initialValue: vm.scheduleStartOnAppLaunch)
        _scheduleLaunchMode       = State(initialValue: vm.scheduleLaunchMode)
        _scheduleForceVMLaunch    = State(initialValue: vm.scheduleForceVMLaunch)
    }

    private static func defaultTime(hour: Int) -> Date {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private var allKnownTags: [String] {
        let fromVMs = vmStore.vms.flatMap { $0.tags }
        let fromStore = tagStore.managedTags
        var freq: [String: Int] = [:]
        for tag in fromVMs { freq[tag, default: 0] += 1 }
        return Array(Set(fromVMs + fromStore))
            .sorted { (freq[$0] ?? 0) > (freq[$1] ?? 0) }
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

    // MARK: - Schedule conflict detection

    /// Other non-base, schedule-enabled VMs that share the same start time and at least one day.
    private var scheduleConflicts: [VirtualMachine] {
        guard scheduleEnabled, scheduleStartTimeEnabled, !scheduleStartDays.isEmpty else { return [] }
        let cal = Calendar.current
        let h = cal.component(.hour,   from: scheduleStartTime)
        let m = cal.component(.minute, from: scheduleStartTime)
        return vmStore.vms.filter { other in
            guard other.id != vm.id,
                  !other.effectivelyBase,
                  other.scheduleEnabled,
                  let ot = other.scheduleStartTime else { return false }
            let oh = cal.component(.hour,   from: ot)
            let om = cal.component(.minute, from: ot)
            return oh == h && om == m && !scheduleStartDays.intersection(other.scheduleStartDays).isEmpty
        }
    }

    private var conflictWarningText: String {
        let names = scheduleConflicts.prefix(2).map { $0.displayName.isEmpty ? $0.name : $0.displayName }
        let extra = scheduleConflicts.count > 2 ? " and \(scheduleConflicts.count - 2) more" : ""
        return "Start time conflict with \(names.joined(separator: ", "))\(extra). Only 2 VMs can run simultaneously — consider Force VM Launch or offset the start time."
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
                        TextField("", text: $displayName, prompt: Text(vm.name).foregroundStyle(.secondary))
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
                                  prompt: Text("What is this VM for?").foregroundStyle(.secondary),
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
                        versionPickerSel = ""
                        customVersionText = ""
                        customOSMajorVersion = ""
                        customOSReleaseName = ""
                        Task { await loadVersions(for: newOS) }
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
                            Text("Any").tag("")
                            ForEach(versionList, id: \.self) { v in Text(v).tag(v) }
                            Divider()
                            Text("Custom…").tag(Self.customVersionSentinel)
                        }
                        .onChange(of: versionPickerSel) { _, sel in
                            if sel != Self.customVersionSentinel { customVersionText = "" }
                        }
                        if isFetchingVersions {
                            ProgressView().controlSize(.mini).padding(.leading, 4)
                        }
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
                    LabeledContent("Serial Number") {
                        TextField("", text: $serialNumber, prompt: Text(vm.serialNumber).foregroundStyle(.secondary))
                    }
                }

                if theme.mdmEnabled && !serverStore.servers.isEmpty {
                    Section {
                        Picker("MDM Server", selection: $mdmServerID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(serverStore.servers) { server in
                                Text(server.friendlyName).tag(Optional(server.id))
                            }
                        }
                        if mdmServerID != nil && vm.serialNumber.count < 10 {
                            Label("Set a serial number (≥ 10 chars) to enable enrollment lookup.",
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("MDM") }
                      footer: { Text("Link this VM to an MDM server to look up its enrollment status.") }
                }

                Section("Default VM and SSH credentials") {
                    LabeledContent("Username") {
                        TextField("", text: $sshUsername,
                                  prompt: Text("e.g. baker").foregroundStyle(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Password") {
                        HStack(spacing: 6) {
                            let prompt = Text(vm.sshPassword != nil ? "Stored in Keychain" : "No password set")
                                .foregroundStyle(.secondary)
                            Group {
                                if isPasswordRevealed {
                                    TextField("", text: $sshPassword, prompt: prompt)
                                } else {
                                    SecureField("", text: $sshPassword, prompt: prompt)
                                }
                            }
                            .multilineTextAlignment(.trailing)
                            .onChange(of: sshPassword) { _, _ in isPasswordRevealed = false }

                            if isAuthenticatingPassword {
                                ProgressView().controlSize(.mini)
                            } else if !sshPassword.isEmpty {
                                Button {
                                    if isPasswordRevealed {
                                        isPasswordRevealed = false
                                    } else {
                                        Task { await revealEditSheetPassword() }
                                    }
                                } label: {
                                    Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.bordered).controlSize(.mini)
                                .help(isPasswordRevealed ? "Hide password" : "Reveal password")
                            }
                        }
                    }
                }

                Section {
                    Toggle("Supports Tart Guest Agent", isOn: $supportsGuestAgent)
                } header: { Text("Remote Execution") }
                  footer: { Text("Enables 'Execute Command via Guest Agent' using tart exec. Requires tart-guest-agent to be installed inside the VM.") }

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

                // MARK: Schedule section
                scheduleSection
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 480)
        .task {
            await loadVersions(for: osName)
            // After SOFA loads, if the current version is now in the list switch to it
            if versionPickerSel == Self.customVersionSentinel
                && versionList.contains(customVersionText) {
                versionPickerSel = customVersionText
                customVersionText = ""
            }
        }
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

    // MARK: - Schedule section view

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            Toggle("Enable schedule", isOn: $scheduleEnabled)

            if scheduleEnabled {
                // Start
                Toggle(isOn: $scheduleStartTimeEnabled) {
                    Label("Scheduled start", systemImage: "play.circle")
                }
                if scheduleStartTimeEnabled {
                    DatePicker("Start at", selection: $scheduleStartTime,
                               displayedComponents: .hourAndMinute)
                    LabeledContent("Start on") {
                        WeekdayPicker(selection: $scheduleStartDays)
                    }
                    if scheduleStartTimeEnabled && scheduleStartDays.isEmpty {
                        Label("Select at least one day for the start schedule to fire.",
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Stop
                Toggle(isOn: $scheduleStopTimeEnabled) {
                    Label("Scheduled stop", systemImage: "stop.circle")
                }
                if scheduleStopTimeEnabled {
                    DatePicker("Stop at", selection: $scheduleStopTime,
                               displayedComponents: .hourAndMinute)
                    LabeledContent("Stop on") {
                        WeekdayPicker(selection: $scheduleStopDays)
                    }
                    if scheduleStopTimeEnabled && scheduleStopDays.isEmpty {
                        Label("Select at least one day for the stop schedule to fire.",
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle("Start on app launch", isOn: $scheduleStartOnAppLaunch)

                Picker("Start mode", selection: $scheduleLaunchMode) {
                    ForEach(VMScheduleLaunchMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                }

                Toggle("Force VM launch", isOn: $scheduleForceVMLaunch)
            }
        } header: {
            Text("Schedule")
        } footer: {
            if scheduleEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    if !scheduleConflicts.isEmpty {
                        Label(conflictWarningText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if scheduleForceVMLaunch {
                        Label("Force launch stops the most recently started VM when 2 are already running.",
                              systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    Label("Requires Oven to be running. VMs will not start or stop automatically when Oven is closed.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func loadVersions(for release: MacOSRelease.Name) async {
        isFetchingVersions = true
        sofaVersions = await SOFAService.shared.versions(for: release)
        isFetchingVersions = false
    }

    @MainActor private func revealEditSheetPassword() async {
        isAuthenticatingPassword = true
        let context = LAContext()
        let name = vm.displayName.isEmpty ? vm.name : vm.displayName
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "Reveal SSH password for \(name)") { ok, _ in
                c.resume(returning: ok)
            }
        }
        if granted { isPasswordRevealed = true }
        isAuthenticatingPassword = false
    }

    private func save() {
        vmStore.updateMetadata(id: vm.id) { v in
            let trimmed = displayName.trimmingCharacters(in: .whitespaces)
            v.displayName   = trimmed.isEmpty ? (tartName.isEmpty ? vm.name : tartName) : trimmed
            v.description   = description
            v.tags          = tags
            v.sshUsername        = sshUsername
            v.supportsGuestAgent = supportsGuestAgent
            v.sharedFolders      = sharedFolders
            v.cpuCount      = cpuCount
            v.memoryGB      = memoryGB
            v.osName               = osName
            v.osVersion            = resolvedOSVersion
            v.isBetaOS             = isBetaOS
            v.betaLabel            = betaLabel.trimmingCharacters(in: .whitespaces)
            v.customOSMajorVersion = customOSMajorVersion.trimmingCharacters(in: .whitespaces)
            v.customOSReleaseName  = customOSReleaseName.trimmingCharacters(in: .whitespaces)
            v.serialNumber         = serialNumber
            v.mdmServerID   = mdmServerID
            v.sshPassword   = sshPassword.isEmpty ? nil : sshPassword
            if !v.isOCIBased {
                v.isBaseVM = isBaseVM
                // A VM already present in tart is by definition built — fix stale notBuilt status
                if isBaseVM && v.buildStatus == .notBuilt { v.buildStatus = .ready }
            }
            // Schedule
            v.scheduleEnabled          = scheduleEnabled
            v.scheduleStartTime        = scheduleEnabled && scheduleStartTimeEnabled ? scheduleStartTime : nil
            v.scheduleStartDays        = scheduleStartDays
            v.scheduleStopTime         = scheduleEnabled && scheduleStopTimeEnabled ? scheduleStopTime : nil
            v.scheduleStopDays         = scheduleStopDays
            v.scheduleStartOnAppLaunch = scheduleStartOnAppLaunch
            v.scheduleLaunchMode       = scheduleLaunchMode
            v.scheduleForceVMLaunch    = scheduleForceVMLaunch
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

// MARK: - WeekdayPicker

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                let selected = selection.contains(index)
                Button {
                    if selected { selection.remove(index) }
                    else        { selection.insert(index) }
                } label: {
                    Text(labels[index])
                        .font(.caption2.bold())
                        .frame(width: 24, height: 24)
                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: Circle())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(fullDayName(index))
            }
        }
    }

    private func fullDayName(_ index: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[index]
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
                    TextField("", text: $name, prompt: Text("e.g. projects").foregroundStyle(.secondary))
                }
                Section("Host path") {
                    HStack {
                        TextField("", text: $hostPath, prompt: Text("/Users/you/Projects").foregroundStyle(.secondary))
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
