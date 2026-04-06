import SwiftUI

// MARK: - PreferencesView
// MARK: - PreferencesView (tabbed)

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            BuildPrefsTab()
                .tabItem { Label("Build", systemImage: "hammer") }

            StoragePrefsTab()
                .tabItem { Label("Storage", systemImage: "externaldrive") }

            NotificationPrefsTab()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }

            IntegrationsPrefsTab()
                .tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }
            TagsPrefsTab()
                .tabItem { Label("Tags", systemImage: "tag") }
        }
        .frame(minWidth: 540, minHeight: 400)
    }
}
