import SwiftUI

struct GeneralPrefsTab: View {
    @EnvironmentObject var theme: AppTheme

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
                Button(role: .destructive) {
                    theme.funModeEnabled = false
                    theme.debugModeEnabled = false
                } label: {
                    Label("Reset General Settings to Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Restores Fun Mode and Debug Mode to their default (off) state.")
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
