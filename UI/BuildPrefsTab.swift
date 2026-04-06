import SwiftUI

struct BuildPrefsTab: View {
    @EnvironmentObject var theme: AppTheme
    @State private var settings = AppSettings.load()

    // Default hardware
    @AppStorage("defaultCPUCount")  private var defaultCPU: Int = 4
    @AppStorage("defaultMemoryGB")  private var defaultMemory: Int = 8
    @AppStorage("defaultDiskGB")    private var defaultDisk: Int = 80

    // Default credentials — usernames in UserDefaults, passwords in Keychain
    @AppStorage("defaultPackerUsername")   private var packerUsername: String = "baker"
    @State private var packerPassword: String = ""

    var body: some View {
        Form {
            Section {
                Picker("CPU cores", selection: $defaultCPU) {
                    ForEach([2, 4, 6, 8, 10, 12, 16], id: \.self) { Text("\($0) cores").tag($0) }
                }
                Picker("Memory", selection: $defaultMemory) {
                    ForEach([4, 8, 12, 16, 24, 32, 48, 64], id: \.self) { Text("\($0) GB").tag($0) }
                }
                Picker("Disk", selection: $defaultDisk) {
                    ForEach([40, 60, 80, 100, 120, 150, 200, 250, 500], id: \.self) { Text("\($0) GB").tag($0) }
                }
            } header: { Text("Default hardware") }
              footer: { Text("Applied when creating new Base VMs and cloning VMs. Can be overridden per-VM.") }

            Section {
                LabeledContent("Username") {
                    TextField("", text: $packerUsername,
                              prompt: Text("e.g. baker").foregroundColor(.secondary))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Password") {
                    SecureField("", text: $packerPassword)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: packerPassword) { _, v in
                            KeychainService.store(key: "defaults.packer.password", value: v)
                        }
                }
            } header: { Text("Default Packer credentials") }
              footer: { Text("Used for Base VMs built from Packer templates. Stored securely in Keychain.") }

            Section {
                Stepper(value: $theme.buildTimeoutMinutes, in: 30...600, step: 15) {
                    LabeledContent("Timeout") {
                        Text("\(theme.buildTimeoutMinutes) min").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $theme.buildHeartbeatMinutes, in: 1...60, step: 1) {
                    LabeledContent("Heartbeat warning") {
                        Text("\(theme.buildHeartbeatMinutes) min").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $theme.batteryThresholdPct, in: 0...100, step: 5) {
                    LabeledContent("Min. battery") {
                        Text("\(Int(theme.batteryThresholdPct))%").foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Safeguards") }
              footer: { Text("Oven aborts a build exceeding the timeout, warns if no output arrives within the heartbeat interval, and blocks builds when battery is below the threshold.") }

            Section {
                Toggle(isOn: $theme.preventSleepDuringBuild) {
                    Label("Prevent sleep during build", systemImage: "moon.zzz")
                }
                Toggle(isOn: $theme.showGraphicsDuringBuild) {
                    Label("Show VM window during build", systemImage: "display")
                }
                if theme.showGraphicsDuringBuild {
                    Text("The tart window will be visible. Do not interact with it while the setup assistant is running.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle(isOn: $theme.lockInputDuringBuild) {
                    Label("Lock input during build", systemImage: "lock.fill")
                }
                if theme.lockInputDuringBuild {
                    Text("Requires Accessibility permission. Press ⌘⇧⎋ or click Unlock to restore input.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $theme.showUnlockHintOverlay) {
                    Label("Show unlock hint overlay", systemImage: "lock.open")
                }
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

                if settings.ipswDownloadMode == .mistCli {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("mist-cli will be found automatically from your PATH or Oven's managed copy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("IPSW download") }
              footer: { Text("ipsw.me queries Apple directly — no extra tools needed. mist-cli offers more control for authenticated access or custom mirrors.") }
        }
        .formStyle(.grouped)
        .onAppear {
            packerPassword   = KeychainService.retrieve(key: "defaults.packer.password") ?? ""
        }
        .navigationTitle("Build")
    }
}
