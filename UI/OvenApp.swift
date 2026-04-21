import SwiftUI

/// Shared weak reference so AppDelegate can reach VMStore without
/// going through the SwiftUI environment (which has race conditions on launch).
enum SharedStores {
    static var vmStore: VMStore?
    static var baseVMStore: BaseVMStore?
    static var appState: AppState?
    static var packerService: PackerService?
    static var recipesViewModel: RecipesViewModel?
    /// Set to true before an intentional relaunch to bypass the quit guard.
    static var skipQuitGuard = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !SharedStores.skipQuitGuard else { return .terminateNow }

        // Check running VMs
        if let vmStore = SharedStores.vmStore {
            let running = vmStore.vms.filter { $0.status == .running || $0.status == .suspended }
            if !running.isEmpty {
                let names = running.map { $0.displayName.isEmpty ? $0.name : $0.displayName }
                let list = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
                let alert = NSAlert()
                alert.messageText = "\(running.count) VM\(running.count == 1 ? "" : "s") still running"
                alert.informativeText = "\(list) \(running.count == 1 ? "is" : "are") still running. Stop them before quitting to avoid data loss."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Quit Anyway")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            }
        }

        // Check active Base VM builds
        if let baseVMStore = SharedStores.baseVMStore, baseVMStore.isBuilding {
            let alert = NSAlert()
            alert.messageText = "Base VM build in progress"
            alert.informativeText = "A Base VM is currently being built. Quitting now will cancel the build and may leave a partial VM."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }

        // Check unsaved recipe edits (templates, vars files, building blocks)
        if let rvm = SharedStores.recipesViewModel, rvm.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Unsaved changes in Recipes"
            alert.informativeText = "You have unsaved edits in one or more templates, variables files, or building blocks. They will be lost if you quit."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }

        // Check active downloads (IPSW + registry pulls)
        if let appState = SharedStores.appState {
            let ipswCount = appState.activeIPSWDownloads.count
            let pullCount = appState.registryDownloads.count
            let total = ipswCount + pullCount
            if total > 0 {
                var items: [String] = []
                if ipswCount > 0 { items.append("\(ipswCount) IPSW download\(ipswCount == 1 ? "" : "s")") }
                if pullCount > 0 { items.append("\(pullCount) registry pull\(pullCount == 1 ? "" : "s")") }
                let alert = NSAlert()
                alert.messageText = "Downloads in progress"
                alert.informativeText = "\(items.joined(separator: " and ")) will be cancelled if you quit."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Quit Anyway")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            }
        }

        return .terminateNow
    }
}

@main
struct OvenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var depManager = DependencyManager(
        storageRoot: AppSettings.defaultLocalStorageRoot
    )
    @State private var appState   = AppState()
    @State private var theme      = AppTheme()
    @State private var logger     = AppLogger.shared
    @State private var serverStore  = MDMServerStore()
    @State private var buildSession = BuildSessionManager.shared
    @State private var tagStore = TagStore()
    @State private var vmStore = OvenApp.makeVMStore()
    @State private var baseVMStore = OvenApp.makeBaseVMStore()
    @State private var templateStore = PackerTemplateStore()
    @State private var blockStore = BuildingBlockStore()
    @State private var recipesViewModel = RecipesViewModel()

    // MARK: - Store factories (called once at app launch)

    private static func makeVMStore() -> VMStore {
        let settings = AppSettings.load()
        let tartPath = resolvedTartPath()
        let tartSvc  = TartService(runner: ProcessRunner(), tartPath: tartPath)
        return VMStore(tartService: tartSvc, storageRoot: settings.vmStorageRoot)
    }

    private static func makePackerService() -> PackerService {
        let settings  = AppSettings.load()
        let packerPath = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/packer").path
        let pluginDir  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path
        return PackerService(
            runner: ProcessRunner(),
            packerPath: packerPath,
            pluginDir: pluginDir,
            templatesRoot: settings.packerTemplatesRoot
        )
    }

    private static func makeBaseVMStore() -> BaseVMStore {
        let settings   = AppSettings.load()
        let runner     = ProcessRunner()
        let tartPath   = resolvedTartPath()
        let packerPath = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/packer").path
        let pluginDir  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path
        let tartSvc    = TartService(runner: runner, tartPath: tartPath)
        let packerSvc  = PackerService(
            runner: runner,
            packerPath: packerPath,
            pluginDir: pluginDir,
            templatesRoot: settings.packerTemplatesRoot
        )
        return BaseVMStore(packerService: packerSvc, tartService: tartSvc,
                           storageRoot: settings.packerTemplatesRoot)
    }

    private static func resolvedTartPath() -> String {
        let tartAppBinary = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart")
        return FileManager.default.fileExists(atPath: tartAppBinary.path)
            ? tartAppBinary.path
            : AppSettings.defaultLocalStorageRoot
                .appendingPathComponent("deps/tart").path
    }

    var body: some Scene {
        WindowGroup("Oven — macOS VM Manager powered by Tart") {
            Group {
                if depManager.allReady {
                    AppRootView()
                        .tint(.orange)
                        .environmentObject(depManager)
                        .environmentObject(appState)
                        .environmentObject(theme)
                        .environmentObject(logger)
                        .environmentObject(serverStore)
                        .environmentObject(buildSession)
                        .environmentObject(tagStore)
                        .environmentObject(vmStore)
                        .environmentObject(baseVMStore)
                        .environmentObject(templateStore)
                        .environmentObject(blockStore)
                        .environment(recipesViewModel)
                } else {
                    SetupView(depManager: depManager)
                }
            }
            .task {
                // Wire vmStore into baseVMStore (Option B architecture)
                baseVMStore.vmStore = vmStore
                SharedStores.vmStore = vmStore
                SharedStores.baseVMStore = baseVMStore
                SharedStores.packerService = OvenApp.makePackerService()
                await depManager.bootstrap()
                // Log OS version check at startup
                let ver = ProcessInfo.processInfo.operatingSystemVersion
                if ver.majorVersion < 13 {
                    AppLogger.shared.warning(
                        "macOS \(ver.majorVersion).\(ver.minorVersion) detected. Oven requires macOS 13 Ventura or later.",
                        source: "OvenApp"
                    )
                } else {
                    AppLogger.shared.log(
                        "macOS \(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion) — OK",
                        source: "OvenApp"
                    )
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1160, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            PreferencesView()
                .environmentObject(theme)
                .environmentObject(tagStore)
                .environmentObject(vmStore)
                .environmentObject(baseVMStore)
        }
    }
}

// MARK: - AppRootView

struct AppRootView: View {
    @EnvironmentObject var depManager: DependencyManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var vmStore: VMStore
    @EnvironmentObject var baseVMStore: BaseVMStore
    @Environment(RecipesViewModel.self) private var recipesViewModel

    /// Remove leftover oven-ssh-*.command files from previous sessions
    private func cleanupSSHTempFiles() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let files = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("oven-ssh-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    var body: some View {
        ContentView()
            .task {
                SharedStores.vmStore = vmStore
                SharedStores.baseVMStore = baseVMStore
                SharedStores.appState = appState
                SharedStores.recipesViewModel = recipesViewModel
                await vmStore.sync()
                for tag in Set(vmStore.vms.flatMap { $0.tags }) {
                    if tagStore.colors[tag] == nil {
                        tagStore.setColor(tagColor(for: tag), for: tag)
                    }
                }
            }
            .task { cleanupSSHTempFiles() }
    }
}
