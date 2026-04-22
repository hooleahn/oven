import SwiftUI
import AppKit

// MARK: - MenuBarViewModel
//
// Drives the menu bar extra. Reads from SharedStores (same pattern as AppDelegate)
// so it works outside the main SwiftUI environment hierarchy.
//
// Cached properties (cachedDisplayVMs, cachedHasActiveVMs) are stored @Observable
// properties so SwiftUI can track them correctly. Direct access to
// SharedStores.vmStore?.vms would not be tracked by SwiftUI observation.

@MainActor
@Observable
final class MenuBarViewModel {

    // MARK: - Cached state (observed by SwiftUI)

    private(set) var cachedDisplayVMs: [VirtualMachine] = []
    private(set) var cachedHasActiveVMs: Bool = false

    // MARK: - Private

    private var syncTimer: Timer?

    private var vmStore: VMStore? { SharedStores.vmStore }
    private var appState: AppState? { SharedStores.appState }

    // MARK: - Init / Deinit

    init() {
        startSyncTimer()
    }

    deinit {
        syncTimer?.invalidate()
    }

    // MARK: - Timer

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.vmStore?.sync()
                self.refreshCache()
            }
        }
        // Populate immediately so the menu isn't blank while waiting for first tick
        refreshCache()
    }

    // MARK: - Cache refresh

    func refreshCache() {
        let all = (vmStore?.vms ?? [])
            .filter { !$0.effectivelyBase }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        cachedDisplayVMs = all
        cachedHasActiveVMs = all.contains { $0.status == .running || $0.status == .suspended }
    }

    // MARK: - Start

    /// Start a stopped VM with the given launch mode, tracking the operation in AppState.
    func startVM(_ vm: VirtualMachine, mode: TartService.RunMode) {
        guard let store = vmStore, let state = appState else { return }
        guard vm.status == .stopped, !vm.effectivelyBase else { return }

        Task {
            let label = vm.displayName.isEmpty ? vm.name : vm.displayName
            let opID = state.beginOperation(vmName: label, kind: .start)
            let stream = await store.start(vm: vm, mode: mode)
            await StreamConsumer.consume(stream) { line in
                state.appendLog(operationID: opID, line: line)
            }
            state.finishOperation(id: opID)
            await store.sync()
            refreshCache()
        }
    }

    // MARK: - Stop single VM (with confirmation)

    /// Show an NSAlert to confirm stopping a single VM, then stop it.
    /// NSAlert.runModal() is safe here — menu actions always fire on the main thread.
    func confirmAndStopVM(_ vm: VirtualMachine) {
        guard let store = vmStore else { return }
        guard vm.status == .running || vm.status == .suspended else { return }

        let label = vm.displayName.isEmpty ? vm.name : vm.displayName
        let alert = NSAlert()
        alert.messageText = "Stop \"\(label)\"?"
        alert.informativeText = "The VM will be sent a shutdown signal and given 30 seconds to stop gracefully."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            try? await store.stop(vm: vm)
            await store.sync()
            refreshCache()
        }
    }

    // MARK: - Stop All (with confirmation)

    /// Show an NSAlert to confirm stopping all running/suspended VMs.
    func confirmAndStopAll() {
        guard let store = vmStore else { return }
        let active = cachedDisplayVMs.filter { $0.status == .running || $0.status == .suspended }
        guard !active.isEmpty else { return }

        let count = active.count
        let alert = NSAlert()
        alert.messageText = "Stop All Running VMs?"
        alert.informativeText = "This will stop \(count) VM\(count == 1 ? "" : "s"). Each will be given 30 seconds to shut down gracefully."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop All")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for vm in active {
            Task {
                try? await store.stop(vm: vm)
            }
        }
        Task {
            await store.sync()
            refreshCache()
        }
    }

    // MARK: - Open Main Window

    /// Activate the app and bring the main window to front.
    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title.contains("Oven") {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
