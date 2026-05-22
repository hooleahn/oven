import SwiftUI
import ServiceManagement

struct GeneralPrefsTab: View {
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var vmStore: VMStore
    @AppStorage("toast.disabled") private var toastsDisabled = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $theme.funModeEnabled) {
                    Label("Fun Mode", systemImage: "party.popper")
                }
                .help("Renames technical labels to baking/tart terminology throughout the app.")

                if theme.funModeEnabled {
                    Text("Virtual Machines → Tarts · Base VMs → Recipes · Build → Bake · Registry → Pantry")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle(isOn: $theme.debugModeEnabled) {
                    Label("Debug Mode", systemImage: "ant")
                }
                .help("Logs full command paths, file paths, and variable file contents to the Activity Log before each build.")

                if theme.debugModeEnabled {
                    Text("Logs full command paths, file paths, and vars file contents to the Activity Log before each build.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Fun Mode and Debug Mode are purely cosmetic and diagnostic. They do not affect how VMs are built or run.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $theme.menuBarItemEnabled) {
                    Label("Show Menu Bar Item", systemImage: "menubar.rectangle")
                }
                .help("Shows an Oven icon in the menu bar for quick access to running VMs without opening the main window.")


            } header: {
                Text("Menu Bar")
            }

            Section {
                Toggle(isOn: $launchAtLogin) {
                    Label("Launch at Login", systemImage: "arrow.right.circle")
                }
                .help("Automatically opens Oven when you log in to your Mac.")
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle(isOn: $toastsDisabled) {
                    Label("Disable Error Banners", systemImage: "bell.slash")
                }
                .help("Hides the in-app toast banners that appear when errors are logged. Errors are still recorded in the Activity Log.")

                if toastsDisabled {
                    Text("Error banners are suppressed. Check the Activity Log for errors.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                let suppressedCount = vmStore.suppressedGhostCount
                LabeledContent("Missing VM alerts") {
                    HStack(spacing: 8) {
                        if suppressedCount > 0 {
                            Text("\(suppressedCount) suppressed")
                                .foregroundStyle(.secondary)
                        }
                        Button("Reset") {
                            vmStore.resetGhostSuppression()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(suppressedCount == 0)
                    }
                }
                .help("Re-enables the \"VM not found in tart\" alert for any VMs you previously chose to never notify about.")
            } header: {
                Text("In-App Notifications")
            }

            Section {
                Button(role: .destructive) {
                    theme.funModeEnabled = false
                    theme.debugModeEnabled = false
                    theme.menuBarItemEnabled = true
                    toastsDisabled = false
                } label: {
                    Label("Reset General Settings to Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Restores Fun Mode, Debug Mode, Menu Bar Item, and error banners to their default state.")
            } header: {
                Text("Reset")
            } footer: {
                Text("This only resets settings on this tab. Other preference tabs are unaffected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
