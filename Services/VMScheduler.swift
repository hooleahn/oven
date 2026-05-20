import Foundation

// MARK: - VMScheduler

/// Fires every 30 s, starts/stops VMs whose schedule matches the current time,
/// and handles "start on app launch" VMs. Wire up once at app launch via start(vmStore:).
@MainActor
final class VMScheduler {

    static let shared = VMScheduler()
    private init() {}

    private var timer: Timer?
    private var vmStore: VMStore?

    // Tracks "vmID-start" / "vmID-stop" → DateComponents at last fire to avoid double-firing.
    private var lastTrigger: [String: DateComponents] = [:]

    // MARK: - Lifecycle

    func start(vmStore: VMStore) {
        self.vmStore = vmStore
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in VMScheduler.shared.tick() }
        }
    }

    /// Call once after the initial vmStore.sync() to start any "start on app launch" VMs.
    func checkAppLaunch() {
        guard let vmStore else { return }
        for vm in vmStore.vms where !vm.effectivelyBase && vm.scheduleEnabled && vm.scheduleStartOnAppLaunch {
            guard vm.status == .stopped || vm.status == .suspended else { continue }
            Task { await self.launch(vm: vm) }
        }
    }

    // MARK: - Tick

    private func tick() {
        guard let vmStore else { return }
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let rawWeekday = comps.weekday else { return }
        let dayIndex = rawWeekday - 1  // Calendar.weekday is 1-based (1=Sun); convert to 0-based

        for vm in vmStore.vms where !vm.effectivelyBase && vm.scheduleEnabled {
            checkStart(vm: vm, dayIndex: dayIndex, comps: comps, calendar: calendar)
            checkStop(vm: vm, dayIndex: dayIndex, comps: comps, calendar: calendar)
        }
    }

    private func checkStart(vm: VirtualMachine, dayIndex: Int,
                            comps: DateComponents, calendar: Calendar) {
        guard let startTime = vm.scheduleStartTime,
              !vm.scheduleStartDays.isEmpty,
              vm.scheduleStartDays.contains(dayIndex),
              vm.status == .stopped || vm.status == .suspended else { return }

        let sc = calendar.dateComponents([.hour, .minute], from: startTime)
        guard sc.hour == comps.hour, sc.minute == comps.minute else { return }

        let key = "\(vm.id.uuidString)-start"
        guard !alreadyFired(key: key, comps: comps) else { return }
        lastTrigger[key] = comps
        Task { await self.launch(vm: vm) }
    }

    private func checkStop(vm: VirtualMachine, dayIndex: Int,
                           comps: DateComponents, calendar: Calendar) {
        guard let stopTime = vm.scheduleStopTime,
              !vm.scheduleStopDays.isEmpty,
              vm.scheduleStopDays.contains(dayIndex),
              vm.status == .running else { return }

        let sc = calendar.dateComponents([.hour, .minute], from: stopTime)
        guard sc.hour == comps.hour, sc.minute == comps.minute else { return }

        let key = "\(vm.id.uuidString)-stop"
        guard !alreadyFired(key: key, comps: comps) else { return }
        lastTrigger[key] = comps
        Task { await self.scheduledStop(vm: vm) }
    }

    private func alreadyFired(key: String, comps: DateComponents) -> Bool {
        guard let last = lastTrigger[key] else { return false }
        return last.weekday == comps.weekday
            && last.hour == comps.hour
            && last.minute == comps.minute
    }

    // MARK: - Actions

    func launch(vm: VirtualMachine) async {
        guard let vmStore else { return }
        let name = vm.displayName.isEmpty ? vm.name : vm.displayName

        let running = vmStore.runningVMs
        if running.count >= 2 {
            if vm.scheduleForceVMLaunch {
                // Stop the most recently launched VM to make room
                guard let newest = running.max(by: {
                    ($0.lastStartedAt ?? .distantPast) < ($1.lastStartedAt ?? .distantPast)
                }) else { return }
                let stoppedName = newest.displayName.isEmpty ? newest.name : newest.displayName
                AppLogger.shared.log(
                    "Scheduled launch: stopping '\(stoppedName)' to make room for '\(name)'",
                    source: "VMScheduler")
                try? await vmStore.stop(vm: newest)
                // Brief pause for tart to release resources
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                AppLogger.shared.warning(
                    "Scheduled launch skipped — max VMs running (\(name))", source: "VMScheduler")
                await NotificationService.shared.notifyVMStartFailed(
                    vmName: name, reason: "Maximum concurrent VMs (2) are already running.")
                return
            }
        }

        let launchMode: TartService.RunMode
        switch vm.scheduleLaunchMode {
        case .native:   launchMode = .native
        case .vnc:      launchMode = .vnc
        case .headless: launchMode = .headless
        }

        let stream = await vmStore.start(vm: vm, mode: launchMode)
        await NotificationService.shared.notifyVMStarted(vmName: name)
        AppLogger.shared.success("Scheduled launch: \(name)", source: "VMScheduler")

        // Consume the stream so the tart process stays alive; sync status when it ends.
        Task { @MainActor in
            for await _ in stream {}
            await vmStore.sync()
        }
    }

    private func scheduledStop(vm: VirtualMachine) async {
        guard let vmStore else { return }
        let name = vm.displayName.isEmpty ? vm.name : vm.displayName
        do {
            try await vmStore.stop(vm: vm)
            AppLogger.shared.success("Scheduled stop: \(name)", source: "VMScheduler")
        } catch {
            AppLogger.shared.error(
                "Scheduled stop failed for \(name): \(error.localizedDescription)",
                source: "VMScheduler")
        }
    }
}
