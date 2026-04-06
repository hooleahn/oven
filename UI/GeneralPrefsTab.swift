import SwiftUI

struct GeneralPrefsTab: View {
    @EnvironmentObject var theme: AppTheme

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $theme.funModeEnabled) {
                    Label("Fun Mode", systemImage: "party.popper")
                }
                if theme.funModeEnabled {
                    Text("Virtual Machines → Tarts · Base VMs → Recipes · Build → Bake · Registry → Pantry")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $theme.debugModeEnabled) {
                    Label("Debug Mode", systemImage: "ant")
                }
                if theme.debugModeEnabled {
                    Text("Logs full command paths, file paths, and vars file contents to the Activity Log before each build.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Appearance") }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
