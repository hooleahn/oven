import SwiftUI

/// Shared weak reference so AppDelegate can reach VMStore without
/// going through the SwiftUI environment (which has race conditions on launch).
enum SharedStores {
    static var vmStore: VMStore?
    static var baseVMStore: BaseVMStore?
    static var appState: AppState?
    static var packerService: PackerService?
    static var recipesViewModel: RecipesViewModel?
    static var pushManager: PushManager?
    /// Set to true before an intentional relaunch to bypass the quit guard.
    static var skipQuitGuard = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !SharedStores.skipQuitGuard else { return .terminateNow }

        // Gather every active background operation into one list so the user sees
        // the full picture in a single dialog — quitting with a VM running but an
        // installer download or registry pull also in flight shouldn't silently
        // drop the download while only warning about the VM.
        let runningVMs = SharedStores.vmStore?.vms.filter {
            $0.status == .running || $0.status == .suspended
        } ?? []
        let buildingBaseVMs = SharedStores.baseVMStore?.isBuilding == true ? 1 : 0
        let ipswCount = SharedStores.appState?.activeIPSWDownloads.count ?? 0
        let pullCount = SharedStores.appState?.registryDownloads.count ?? 0
        let pushCount = SharedStores.pushManager?.active.count ?? 0

        var lines: [String] = []
        if !runningVMs.isEmpty {
            let names = runningVMs.map { $0.displayName.isEmpty ? $0.name : $0.displayName }
            let list = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
            lines.append("• \(runningVMs.count) VM\(runningVMs.count == 1 ? "" : "s") running (\(list))")
        }
        if buildingBaseVMs > 0 {
            lines.append("• \(buildingBaseVMs) Base VM build\(buildingBaseVMs == 1 ? "" : "s") in progress")
        }
        if ipswCount > 0 {
            lines.append("• \(ipswCount) IPSW download\(ipswCount == 1 ? "" : "s")")
        }
        if pullCount > 0 {
            lines.append("• \(pullCount) registry pull\(pullCount == 1 ? "" : "s")")
        }
        if pushCount > 0 {
            lines.append("• \(pushCount) registry push\(pushCount == 1 ? "" : "es")")
        }

        if !lines.isEmpty {
            let alert = NSAlert()
            alert.messageText = lines.count == 1
                ? "1 operation in progress"
                : "\(lines.count) operations in progress"
            alert.informativeText = "Quitting now will interrupt:\n\n\(lines.joined(separator: "\n"))\n\nRunning VMs will keep their disk state, but downloads, pulls, pushes, and builds will be cancelled."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit Anyway")
            if !runningVMs.isEmpty {
                alert.addButton(withTitle: "Stop VMs and Quit")
            }
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:   // Quit Anyway — fall through
                break
            case .alertSecondButtonReturn where !runningVMs.isEmpty:  // Stop VMs and Quit
                Task { @MainActor in
                    if let vmStore = SharedStores.vmStore {
                        await withTaskGroup(of: Void.self) { group in
                            for vm in runningVMs {
                                group.addTask { try? await vmStore.stop(vm: vm) }
                            }
                        }
                    }
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                return .terminateLater
            default:                        // Cancel
                return .terminateCancel
            }
        }

        // Check unsaved recipe edits (templates, vars files, building blocks) —
        // a data-loss warning about unsaved edits, not a background operation,
        // so it stays a separate dialog.
        if let rvm = SharedStores.recipesViewModel, rvm.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Unsaved changes in Recipes"
            alert.informativeText = "You have unsaved edits in one or more templates, variables files, or building blocks. They will be lost if you quit."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }

        return .terminateNow
    }
}

@main
struct OvenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Mirror of AppTheme.menuBarItemEnabled — used as the isInserted binding
    // for MenuBarExtra. AppTheme's @AppStorage properties don't bridge cleanly
    // to Scene-level bindings, so we keep a dedicated @AppStorage here that
    // reads/writes the same UserDefaults key.
    @AppStorage("menuBarItemEnabled") private var menuBarItemEnabled = true
    // profileStore must be declared before vmStore/baseVMStore so ProfileStore.init()
    // switches AppDatabase.root before the store factories read from it.
    @State private var profileStore  = ProfileStore()
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
    @State private var menuBarViewModel = MenuBarViewModel()
    @State private var pushManager = PushManager()
    @State private var customOSStore = CustomOSStore()
    @State private var installerStore = InstallerStore()

    // Ensure AppDatabase uses the active profile's root before any @State store
    // initialises — @State init order is not guaranteed in SwiftUI.
    init() {
        ProfileStore.bootstrapActiveProfile()
    }

    // MARK: - Store factories (called once at app launch)

    private static func makeVMStore() -> VMStore {
        let settings = AppSettings.load()
        let tartPath = resolvedTartPath()
        let tartSvc  = TartService(runner: ProcessRunner(), tartPath: tartPath)
        return VMStore(tartService: tartSvc, storageRoot: settings.vmStorageRoot)
    }

    private static func makePackerService() -> PackerService {
        let packerPath = resolvedPackerPath()
        let pluginDir  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path
        return PackerService(
            runner: ProcessRunner(),
            packerPath: packerPath,
            pluginDir: pluginDir
        )
    }

    private static func makeBaseVMStore() -> BaseVMStore {
        let settings   = AppSettings.load()
        let runner     = ProcessRunner()
        let tartPath   = resolvedTartPath()
        let packerPath = resolvedPackerPath()
        let pluginDir  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path
        let tartSvc    = TartService(runner: runner, tartPath: tartPath)
        let packerSvc  = PackerService(
            runner: runner,
            packerPath: packerPath,
            pluginDir: pluginDir
        )
        return BaseVMStore(packerService: packerSvc, tartService: tartSvc,
                           storageRoot: settings.packerTemplatesRoot)
    }

    private static func resolvedTartPath() -> String {
        let settings = AppSettings.load()
        if let custom = settings.effectivePath(for: "tart") { return custom }
        let tartAppBinary = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart")
        return FileManager.default.fileExists(atPath: tartAppBinary.path)
            ? tartAppBinary.path
            : AppSettings.defaultLocalStorageRoot
                .appendingPathComponent("deps/tart").path
    }

    private static func resolvedPackerPath() -> String {
        let settings = AppSettings.load()
        return settings.effectivePath(for: "packer")
            ?? AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps/packer").path
    }

    // MARK: - Menu bar icon label

    @ViewBuilder
    private var menuBarLabel: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .overlay(alignment: .topTrailing) {
                if menuBarViewModel.runningCount > 0 {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .overlay { Circle().stroke(Color(nsColor: .textBackgroundColor), lineWidth: 1) }
                        .offset(x: 3, y: -2)
                }
            }
            .overlay {
                if NSImage(named: "MenuBarIcon") == nil {
                    Image(systemName: "flame.fill")
                }
            }
    }

    var body: some Scene {
        WindowGroup("Oven") {
            Group {
                if depManager.allReady {
                    AppRootView()
                        .tint(Color("AccentColor"))
                        .environment(depManager)
                        .environment(appState)
                        .environment(theme)
                        .environment(logger)
                        .environment(serverStore)
                        .environment(buildSession)
                        .environment(tagStore)
                        .environment(vmStore)
                        .environment(baseVMStore)
                        .environment(templateStore)
                        .environment(blockStore)
                        .environment(pushManager)
                        .environment(profileStore)
                        .environment(customOSStore)
                        .environment(installerStore)
                        .environment(recipesViewModel)
                } else {
                    SetupView(depManager: depManager)
                }
            }
            .onChange(of: profileStore.activeProfileID) { _, _ in
                templateStore.load()
                Task { await vmStore.reload() }
                if let error = AppSettings.load().checkTartHomeAccessibility() {
                    appState.tartHomeAlertMessage = error
                }
            }
            .task {
                // Wire vmStore into baseVMStore (Option B architecture)
                baseVMStore.vmStore = vmStore
                SharedStores.vmStore = vmStore
                SharedStores.baseVMStore = baseVMStore
                SharedStores.packerService = OvenApp.makePackerService()
                SharedStores.pushManager = pushManager
                // Also wire into menuBarViewModel (MenuBarExtra.task may run first,
                // but this ensures the reference is set when the main window opens too)
                menuBarViewModel.vmStore = vmStore
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
                // Check TART_HOME accessibility on startup
                if let error = AppSettings.load().checkTartHomeAccessibility() {
                    appState.tartHomeAlertMessage = error
                }
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1160, height: 720)
        .commands {
            NewItemCommands()
            CommandGroup(after: .help) {
                Button("Show Welcome Guide") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Acknowledgements…") {
                    NotificationCenter.default.post(name: .showAcknowledgements, object: nil)
                }
            }
        }

        Settings {
            PreferencesView()
                .environment(theme)
                .environment(tagStore)
                .environment(vmStore)
                .environment(baseVMStore)
                .environment(depManager)
                .environment(profileStore)
                .environment(serverStore)
                .environment(installerStore)
        }

        MenuBarExtra(isInserted: Binding(
            get:  { menuBarItemEnabled },
            set:  { _ in }
        )) {
            MenuBarMenuContent(model: menuBarViewModel)
                .onAppear {
                    // Wire vmStore before onMenuOpen() runs so computed
                    // properties have data even if the main window is closed.
                    menuBarViewModel.vmStore = vmStore
                }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - File > New command

/// Drives the File > New menu item from whichever sidebar section is currently
/// selected. ContentView publishes the contextual action via `.focusedSceneValue(\.newItemCommand, ...)`.
struct NewItemCommands: Commands {
    @FocusedValue(\.newItemCommand) private var newItemCommand: NewItemCommand?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(newItemCommand?.label ?? "New") {
                newItemCommand?.action()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newItemCommand == nil)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let showOnboarding      = Notification.Name("com.oven.showOnboarding")
    static let showAcknowledgements = Notification.Name("com.oven.showAcknowledgements")
    static let tartHomeInvalid     = Notification.Name("com.oven.tartHomeInvalid")
}

// MARK: - AppRootView

struct AppRootView: View {
    @Environment(DependencyManager.self) private var depManager
    @Environment(AppState.self) private var appState
    @Environment(TagStore.self) private var tagStore
    @Environment(VMStore.self) private var vmStore
    @Environment(BaseVMStore.self) private var baseVMStore
    @Environment(RecipesViewModel.self) private var recipesViewModel

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showAcknowledgements = false

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
                // Start the VM scheduler and handle "start on app launch" VMs
                VMScheduler.shared.start(vmStore: vmStore)
                VMScheduler.shared.checkAppLaunch()
                // Register any VM tags that don't yet have an explicit palette index
                for tag in Set(vmStore.vms.flatMap { $0.tags }) {
                    if tagStore.colorIndices[tag] == nil {
                        // Assign a deterministic palette index based on name hash
                        var hash = 5381
                        for char in tag.unicodeScalars { hash = hash &* 31 &+ Int(char.value) }
                        tagStore.setPaletteIndex(abs(hash) % TagStore.palette.count, for: tag)
                    }
                }
                // Show onboarding on first launch
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
            .task { cleanupSSHTempFiles() }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView { showOnboarding = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                showOnboarding = true
            }
            .sheet(isPresented: $showAcknowledgements) {
                AcknowledgementsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAcknowledgements)) { _ in
                showAcknowledgements = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .tartHomeInvalid)) { notification in
                if let msg = notification.userInfo?["message"] as? String {
                    appState.tartHomeAlertMessage = msg
                }
            }
            .alert("Storage Directory Inaccessible",
                   isPresented: Binding(
                       get: { appState.tartHomeAlertMessage != nil },
                       set: { if !$0 { appState.tartHomeAlertMessage = nil } }
                   )
            ) {
                Button("Open Preferences") {
                    appState.tartHomeAlertMessage = nil
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Button("OK", role: .cancel) { appState.tartHomeAlertMessage = nil }
            } message: {
                Text(appState.tartHomeAlertMessage ?? "")
            }
    }
}
