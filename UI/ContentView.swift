import SwiftUI

// MARK: - Sidebar destination

enum SidebarItem: String, Hashable, CaseIterable {
    case virtualMachines
    case baseVMs
    case recipes
    case installers
    case registry
    case mdmEnrollment
    case mdmServers
    case activityLog
    // Static fallbacks used when AppTheme is not available (e.g. enum context)
    var defaultIcon: String {
        switch self {
        case .virtualMachines: return "desktopcomputer"
        case .baseVMs:         return "shippingbox"
        case .recipes:         return "doc.text"
        case .installers:      return "arrow.down.circle"
        case .registry:        return "externaldrive.connected.to.line.below"
        case .mdmEnrollment:   return "lock.shield"
        case .mdmServers:      return "server.rack"
        case .activityLog:     return "list.bullet.rectangle"
        }
    }

    var defaultLabel: String {
        switch self {
        case .virtualMachines: return "Virtual Machines"
        case .baseVMs:         return "Base VMs"
        case .recipes:         return "Packer Templates"
        case .installers:      return "macOS Installers"
        case .registry:        return "Image Registry"
        case .mdmEnrollment:   return "MDM Enrollment"
        case .mdmServers:      return "MDM Servers"
        case .activityLog:     return "Activity Log"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var theme: AppTheme
    @State private var selection: SidebarItem? = .virtualMachines
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            DetailRouter(selection: selection)
                .navigationSplitViewColumnWidth(min: 500, ideal: 800)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarItem?

    private var runningVMCount: Int {
        vmStore.vms.filter { $0.status == .running || $0.status == .suspended }.count
    }

    private var activeDownloadCount: Int {
        appState.activeIPSWDownloads.count + appState.registryDownloads.count
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                sidebarItem(.virtualMachines, badge: runningVMCount > 0 ? "\(runningVMCount)" : nil)
                sidebarItem(.baseVMs)
                sidebarItem(.recipes)
                sidebarItem(.installers, badge: activeDownloadCount > 0 ? "\(activeDownloadCount)" : nil)
                sidebarItem(.registry)
            } header: {
                SidebarSectionHeader("Library")
            }

            if theme.mdmEnabled {
                Section {
                    sidebarItem(.mdmServers)
                    sidebarItem(.mdmEnrollment)
                } header: {
                    SidebarSectionHeader("MDM")
                }
            }

            Section {
                sidebarItem(.activityLog)
            } header: {
                SidebarSectionHeader("General")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { OvenStatusBar() }
    }

    @ViewBuilder
    private func sidebarItem(_ item: SidebarItem, badge: String? = nil) -> some View {
        Label(themedLabel(item), systemImage: themedIcon(item))
            .badge(badge)
            .tag(item)
    }

    // Resolve themed strings here, on the MainActor via @EnvironmentObject
    private func themedLabel(_ item: SidebarItem) -> String {
        switch item {
        case .virtualMachines: return theme.virtualMachines
        case .baseVMs:         return theme.baseVMs
        case .recipes:         return theme.recipes
        case .installers:      return theme.installers
        case .registry:        return theme.registry
        case .mdmEnrollment:   return theme.mdmEnrollment
        case .mdmServers:      return theme.mdmServers
        case .activityLog:     return theme.logs
        }
    }

    private func themedIcon(_ item: SidebarItem) -> String {
        switch item {
        case .virtualMachines: return theme.vmIcon
        case .baseVMs:         return theme.baseVMIcon
        case .recipes:         return "doc.text"
        case .installers:      return theme.installerIcon
        case .registry:        return theme.registryIcon
        case .mdmEnrollment:   return "lock.shield"
        case .mdmServers:      return "server.rack"
        case .activityLog:     return "list.bullet.rectangle"
        }
    }
}

// MARK: - Sidebar section header

private struct SidebarSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

// MARK: - Status bar

struct OvenStatusBar: View {
    @EnvironmentObject var depManager: DependencyManager
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(depManager.allReady ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(depManager.allReady ? "All tools ready" : "Setting up…")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            // Preferences button — opens the ⌘, Settings window
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Preferences (⌘,)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
    }
}

// MARK: - Detail router

struct DetailRouter: View {
    @EnvironmentObject var theme: AppTheme
    let selection: SidebarItem?

    var body: some View {
        switch selection {
        case .virtualMachines: VMListView()
        case .baseVMs:         BaseVMView()
        case .recipes:         RecipesView()
        case .installers:      InstallerView()
        case .registry:        RegistryView()
        case .mdmEnrollment:   MDMEnrollmentView()
        case .mdmServers:      MDMServersView()
        case .activityLog:     LogView()
        case .none:
            ContentUnavailableView("Select an item", systemImage: "sidebar.left",
                                   description: Text("Choose a section from the sidebar."))
        }
    }
}
