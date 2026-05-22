import SwiftUI
import AppKit

// MARK: - MenuBarViewModel
//
// Drives the menu bar extra. Reads directly from SharedStores.vmStore so
// SwiftUI's @Observable machinery on VMStore propagates changes automatically.
// No separate cache is needed — computed properties below are re-evaluated
// whenever vmStore.vms changes.

@MainActor
@Observable
final class MenuBarViewModel {

    // MARK: - Store reference
    //
    // Held directly rather than read from SharedStores so the menu bar panel
    // has data even before the main window opens (SharedStores.vmStore is only
    // set inside WindowGroup.task, which runs only when the window appears).
    var vmStore: VMStore?

    // All non-base VMs
    private var allVMs: [VirtualMachine] {
        vmStore?.vms.filter { !$0.effectivelyBase } ?? []
    }

    // MARK: - Sections

    /// VMs currently running or suspended, newest first.
    var runningVMs: [VirtualMachine] {
        allVMs
            .filter { $0.status == .running || $0.status == .suspended }
            .sorted { ($0.lastStartedAt ?? .distantPast) > ($1.lastStartedAt ?? .distantPast) }
    }

    /// Up to 3 stopped VMs most recently launched (lastStartedAt), then most recently created.
    /// Running VMs are excluded since they already appear in runningVMs.
    var recentVMs: [VirtualMachine] {
        let runningIDs = Set(runningVMs.map(\.id))
        return allVMs
            .filter { !runningIDs.contains($0.id) && !$0.isPinned }
            .sorted {
                let a = $0.lastStartedAt ?? $0.createdAt
                let b = $1.lastStartedAt ?? $1.createdAt
                return a > b
            }
            .prefix(3)
            .map { $0 }
    }

    /// Up to 5 VMs the user has pinned, alphabetically sorted.
    var pinnedVMs: [VirtualMachine] {
        allVMs
            .filter(\.isPinned)
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
            .prefix(5)
            .map { $0 }
    }

    var runningCount: Int { runningVMs.count }
    var buildingCount: Int {
        vmStore?.vms.filter { $0.effectivelyBase && $0.buildStatus == .building }.count ?? 0
    }

    // MARK: - On menu open

    func onMenuOpen() {
        // Ensure vmStore is wired — SharedStores.vmStore is set when the main
        // window opens, but we want the menu bar to work before that too.
        // We assign here as a fallback; OvenApp.body also assigns it.
        if vmStore == nil {
            vmStore = SharedStores.vmStore
        }
        // Kick a background sync so statuses are fresh.
        Task { await vmStore?.sync() }
    }

    // MARK: - Start VM

    func startVM(_ vm: VirtualMachine, mode: TartService.RunMode) {
        guard let store = vmStore, let state = SharedStores.appState else { return }
        guard vm.status == .stopped, !vm.effectivelyBase else { return }
        Task {
            let label = vm.displayName.isEmpty ? vm.name : vm.displayName
            let opID = state.beginOperation(vmName: label, kind: .start)
            let stream = await store.start(vm: vm, mode: mode)
            let result = await StreamConsumer.consume(stream, onStdout: { line in
                state.appendLog(operationID: opID, line: line)
            })
            state.finishOperation(id: opID)
            if result.exitCode != 0 {
                let errLine = result.stderrLines
                    .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    ?? "tart exited with code \(result.exitCode)"
                AppLogger.shared.error("Failed to start \"\(label)\": \(errLine)", source: "VMStore")
            }
            await store.sync()
        }
    }

    // MARK: - Stop VM

    func stopVM(_ vm: VirtualMachine) {
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
        }
    }

    // MARK: - Toggle pin

    func togglePin(_ vm: VirtualMachine) {
        vmStore?.update(id: vm.id) { $0.isPinned.toggle() }
    }

    // MARK: - Open Main Window

    func openMainWindow() {
        // Activate the app — this brings the existing window to front
        // without closing/reopening it (which corrupts the unified toolbar).
        NSApp.activate(ignoringOtherApps: true)

        // If there's already a visible Oven window, bring it forward.
        if let win = NSApp.windows.first(where: { $0.title == "Oven" && !$0.isMiniaturized }) {
            win.makeKeyAndOrderFront(nil)
            return
        }

        // Window is miniaturized — deminiaturize it.
        if let win = NSApp.windows.first(where: { $0.title == "Oven" }) {
            win.deminiaturize(nil)
            return
        }

        // No window exists yet — trigger the app reopen handler.
        _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
    }

    /// Navigate the main window to a specific VM and select it in the list.
    func focusVM(_ vm: VirtualMachine) {
        openMainWindow()
        // Post after a brief delay so VMListView is visible and observing
        // before the notification fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .menuBarFocusVM, object: nil, userInfo: ["vmID": vm.id]
            )
        }
    }
}

extension Notification.Name {
    static let menuBarFocusVM = Notification.Name("OvenMenuBarFocusVM")
}
