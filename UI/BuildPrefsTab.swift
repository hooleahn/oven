import SwiftUI

struct BuildPrefsTab: View {
    @EnvironmentObject var theme: AppTheme
    @State private var settings = AppSettings.load()

    // Default hardware
    @AppStorage("defaultCPUCount")  private var defaultCPU: Int = 4
    @AppStorage("defaultMemoryGB")  private var defaultMemory: Int = 8
    @AppStorage("defaultDiskGB")    private var defaultDisk: Int = 80

    // Default credentials — usernames in UserDefaults, passwords in Keychain
    @AppStorage("defaultPackerUsername") private var packerUsername: String = "baker"
    @State private var packerPassword: String = ""

    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section {
                Picker("CPU cores", selection: $defaultCPU) {
                    ForEach([2, 4, 6, 8, 10, 12, 16], id: \.self) { Text("\($0) cores").tag($0) }
                }
                .help("Number of virtual CPU cores allocated when creating a new Base VM. Can be changed per VM.")

                Picker("Memory", selection: $defaultMemory) {
                    ForEach([4, 8, 12, 16, 24, 32, 48, 64], id: \.self) { Text("\($0) GB").tag($0) }
                }
                .help("RAM allocated to new Base VMs. Ensure the host has sufficient free memory.")

                Picker("Disk", selection: $defaultDisk) {
                    ForEach([40, 60, 80, 100, 120, 150, 200, 250, 500], id: \.self) { Text("\($0) GB").tag($0) }
                }
                .help("Virtual disk size for new Base VMs. Disk space is allocated lazily on the host.")
            } header: { Text("Default hardware") }
              footer: { Text("Applied when creating new Base VMs and cloning VMs. Can be overridden per-VM.") }

            Section {
                LabeledContent("Username") {
                    TextField("", text: $packerUsername,
                              prompt: Text("e.g. baker").foregroundColor(.secondary))
                        .multilineTextAlignment(.trailing)
                }
                .help("The macOS user account created inside Base VMs during the Packer build.")

                LabeledContent("Password") {
                    SecureField("", text: $packerPassword)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: packerPassword) { _, v in
                            KeychainService.store(key: "defaults.packer.password", value: v)
                        }
                }
                .help("Password for the default Packer account. Stored securely in Keychain — never written to disk in plaintext.")
            } header: { Text("Default Packer credentials") }
              footer: { Text("Used for Base VMs built from Packer templates. Stored securely in Keychain.") }

            Section {
                Stepper(value: $theme.buildTimeoutMinutes, in: 30...600, step: 15) {
                    LabeledContent("Timeout") {
                        Text("\(theme.buildTimeoutMinutes) min").foregroundStyle(.secondary)
                    }
                }
                .help("Oven cancels a build that runs longer than this. Increase for very large Base VM builds.")

                Stepper(value: $theme.buildHeartbeatMinutes, in: 1...60, step: 1) {
                    LabeledContent("Heartbeat warning") {
                        Text("\(theme.buildHeartbeatMinutes) min").foregroundStyle(.secondary)
                    }
                }
                .help("Oven warns in the log if no output is received from packer within this interval. Useful for detecting stalled builds.")

                Stepper(value: $theme.batteryThresholdPct, in: 0...100, step: 5) {
                    LabeledContent("Min. battery") {
                        Text("\(Int(theme.batteryThresholdPct))%").foregroundStyle(.secondary)
                    }
                }
                .help("Builds are blocked when the Mac's battery is below this level. Set to 0% to disable the check.")
            } header: { Text("Safeguards") }
              footer: { Text("Oven aborts a build exceeding the timeout, warns if no output arrives within the heartbeat interval, and blocks builds when battery is below the threshold.") }

            Section {
                Toggle(isOn: $theme.preventSleepDuringBuild) {
                    Label("Prevent sleep during build", systemImage: "moon.zzz")
                }
                .help("Asserts an IOKit power assertion so the Mac doesn't sleep while a build is running.")

                Toggle(isOn: $theme.showGraphicsDuringBuild) {
                    Label("Show VM window during build", systemImage: "display")
                }
                .help("Displays the tart virtual machine window during the build. Do not interact with it while the setup assistant is running.")

                if theme.showGraphicsDuringBuild {
                    Text("The tart window will be visible. Do not interact with it while the setup assistant is running.")
                        .font(.caption).foregroundStyle(.orange)
                }

                Toggle(isOn: $theme.lockInputDuringBuild) {
                    Label("Lock input during build", systemImage: "lock.fill")
                }
                .help("Disables keyboard and mouse input during builds to prevent accidental interruptions. Requires Accessibility permission.")

                if theme.lockInputDuringBuild {
                    Text("Requires Accessibility permission. Press ⌘⇧⎋ or click Unlock to restore input.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle(isOn: $theme.showUnlockHintOverlay) {
                    Label("Show unlock hint overlay", systemImage: "lock.open")
                }
                .help("Shows a hint overlay explaining how to unlock input when the lock is active.")

                if !theme.showUnlockHintOverlay {
                    Text("The screen darkens but no hint text is shown — suitable for unattended builds in secure environments.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Behaviour") }

            Section {
                Picker(selection: $theme.buildCompletionAction) {
                    Label("Do nothing", systemImage: "checkmark.circle").tag("nothing")
                    Label("Lock computer (⌘⌃Q)", systemImage: "lock.laptopcomputer").tag("lock")
                    Label("Shut computer down", systemImage: "power").tag("shutdown")
                } label: {
                    Label("After build completes", systemImage: "flag.checkered")
                }
                .help("Action to perform automatically after every Base VM build finishes, whether it succeeds or fails.")

                if theme.buildCompletionAction == "shutdown" {
                    Text("The computer will shut down after every Base VM build, whether it succeeds or fails.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: { Text("Completion") }

            Section {
                Picker("Download method", selection: $settings.ipswDownloadMode) {
                    Text("ipsw.me API (recommended)").tag(AppSettings.IPSWDownloadMode.ipswMe)
                    Text("mist-cli").tag(AppSettings.IPSWDownloadMode.mistCli)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.ipswDownloadMode) { _, _ in try? settings.save() }
                .help("ipsw.me queries Apple servers directly. mist-cli is a third-party tool that offers more control.")

                if settings.ipswDownloadMode == .mistCli {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("mist-cli will be found automatically from your PATH or Oven's managed copy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("IPSW download") }
              footer: { Text("ipsw.me queries Apple directly — no extra tools needed. mist-cli offers more control for authenticated access or custom mirrors.") }

            Section {
                Button(role: .destructive) { showResetConfirm = true } label: {
                    Label("Reset Build Settings to Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Restores all build settings to their factory defaults. Packer credentials in Keychain are not affected.")
            } header: {
                Text("Reset")
            } footer: {
                Text("Resets hardware defaults, safeguard timers, behaviour toggles, and the completion action. Packer credentials stored in Keychain are not removed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            packerPassword = KeychainService.retrieve(key: "defaults.packer.password") ?? ""
        }
        .navigationTitle("Build")
        .confirmationDialog("Reset Build Settings?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) {
                defaultCPU    = 4
                defaultMemory = 8
                defaultDisk   = 80
                packerUsername = "baker"
                theme.buildTimeoutMinutes    = 180
                theme.buildHeartbeatMinutes  = 10
                theme.batteryThresholdPct    = 80.0
                theme.preventSleepDuringBuild = true
                theme.showGraphicsDuringBuild = false
                theme.lockInputDuringBuild    = false
                theme.showUnlockHintOverlay   = true
                theme.buildCompletionAction   = "nothing"
                settings.ipswDownloadMode     = .ipswMe
                try? settings.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All build settings will be restored to their factory defaults. Packer credentials in Keychain are not affected.")
        }
    }
}
