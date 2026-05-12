import Foundation
import AppKit
import IOKit.pwr_mgt

// MARK: - BuildSessionManager

@MainActor
@Observable
final class BuildSessionManager: ObservableObject {

    static let shared = BuildSessionManager()

    var isLocked = false

    private var sleepAssertionID: IOPMAssertionID = 0
    private var sleepAssertionActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapContext: Unmanaged<BuildSessionManager>?

    private init() {}

    // MARK: - Session lifecycle

    func beginBuildSession(preventSleep: Bool, lockInput: Bool) {
        if preventSleep { acquireSleepAssertion() }
        if lockInput    { enableInputLock() }
        triggerLocalNetworkPermission()
    }

    func endBuildSession() {
        releaseSleepAssertion()
        if isLocked { disableInputLock() }
    }

    /// Closes the macOS Screen Sharing app if it's open from a VNC session.
    func closeVNCIfOpen() {
        let script = """
            tell application "Screen Sharing"
                if it is running then quit
            end tell
            """
        if let s = NSAppleScript(source: script) {
            var err: NSDictionary?
            s.executeAndReturnError(&err)
        }
        AppLogger.shared.log("Screen Sharing closed after build", source: "BuildSessionManager")
    }

    // MARK: - Sleep prevention

    private func acquireSleepAssertion() {
        guard !sleepAssertionActive else { return }
        let reason = "Oven: Building base VM" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
        sleepAssertionActive = (result == kIOReturnSuccess)
        AppLogger.shared.log(
            sleepAssertionActive
                ? "Sleep prevention active"
                : "Sleep prevention failed (code \(result))",
            source: "BuildSessionManager"
        )
    }

    private func releaseSleepAssertion() {
        guard sleepAssertionActive else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionActive = false
        AppLogger.shared.log("Sleep prevention released", source: "BuildSessionManager")
    }

    // MARK: - Local Network permission
    // Sending a UDP broadcast causes macOS to show the Local Network permission prompt.

    func triggerLocalNetworkPermission() {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return }
        defer { Darwin.close(sock) }

        var enable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr        = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = 0
        addr.sin_addr.s_addr = INADDR_BROADCAST

        let payload = "oven".data(using: .utf8)!
        let sent = payload.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                    sendto(sock, buf.baseAddress!, buf.count, 0,
                           addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            AppLogger.shared.warning(
                "Local Network permission may be denied — SSH connections to the VM may fail. " +
                "Grant Local Network access in System Settings › Privacy & Security.",
                source: "BuildSessionManager"
            )
        } else {
            AppLogger.shared.log("Local Network permission requested", source: "BuildSessionManager")
        }
    }

    // MARK: - Input lock
    // CGEventTap suppresses all keyboard/mouse events.
    // Unlock shortcut: Cmd + Shift + Escape.

    func enableInputLock() {
        guard !isLocked else { return }

        // AXIsProcessTrustedWithOptions triggers the system permission prompt if not granted.
        // CGPreflightPostEventAccess only checks silently — never prompts.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            AppLogger.shared.warning(
                "Input lock requires Accessibility permission — Oven has prompted for it. Grant access in System Settings › Privacy & Security › Accessibility, then try again.",
                source: "BuildSessionManager"
            )
            return
        }

        // Build the event mask by OR-ing individual type bits
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .scrollWheel, .otherMouseDown, .otherMouseUp,
        ]
        let mask: CGEventMask = types.reduce(0) { $0 | (1 << $1.rawValue) }

        let retained = Unmanaged.passRetained(self)
        eventTapContext = retained
        let selfPtr = retained.toOpaque()

        // Use .cghidEventTap to intercept at the lowest level before the session
        // This ensures events are blocked even from other apps
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let mgr = Unmanaged<BuildSessionManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            eventTapContext?.release()
            eventTapContext = nil
            AppLogger.shared.warning("Could not create CGEventTap for input lock", source: "BuildSessionManager")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isLocked = true
        AppLogger.shared.log("Input locked — press ⌘⇧⎋ to unlock", source: "BuildSessionManager")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // ⌘⇧⎋ → unlock
        if type == .keyDown {
            let flags   = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 53 {
                Task { @MainActor in self.disableInputLock() }
                return nil
            }
        }
        return nil // suppress everything else
    }

    // MARK: - Build completion actions

    func performBuildCompletionAction() {
        let action = UserDefaults.standard.string(forKey: "buildCompletionAction") ?? "nothing"
        switch action {
        case "lock":
            // Equivalent to ⌘⌃Q — activates the login window / screen lock
            // key code 12 = Q, with command + control modifiers
            let lockScript = "tell application \"System Events\" to key code 12 using {command down, control down}"
            if let s = NSAppleScript(source: lockScript) {
                var err: NSDictionary?
                s.executeAndReturnError(&err)
            }
            AppLogger.shared.log("Screen locked after build completion", source: "BuildSessionManager")

        case "shutdown":
            // Check for apps with unsaved changes before shutting down
            // Ask System Events if any process has unsaved documents
            let checkScript = """
                tell application "System Events"
                    set unsavedApps to name of every process whose has unsaved content is true
                    return unsavedApps
                end tell
                """
            var unsavedApps: [String] = []
            if let checker = NSAppleScript(source: checkScript) {
                var checkErr: NSDictionary?
                let result = checker.executeAndReturnError(&checkErr)
                // Iterate NSAppleEventDescriptor list items via numberOfItems / atIndex
                let count = result.numberOfItems
                if count > 0 {
                    for i in 1...count {
                        if let name = result.atIndex(i)?.stringValue {
                            unsavedApps.append(name)
                        }
                    }
                }
            }

            if !unsavedApps.isEmpty {
                let apps = unsavedApps.joined(separator: ", ")
                AppLogger.shared.warning(
                    "Shutdown cancelled — unsaved documents in: \(apps). Save your work first.",
                    source: "BuildSessionManager"
                )
                // Send a notification about the cancelled shutdown
                Task {
                    await NotificationService.shared.notifyBuildComplete(
                        vmName: "Post-build shutdown",
                        success: false,
                        detail: "Shutdown cancelled — unsaved changes in: \(apps)"
                    )
                }
            } else {
                // Graceful shutdown via AppleScript
                let shutdownScript = "tell application \"System Events\" to shut down"
                if let s = NSAppleScript(source: shutdownScript) {
                    var err: NSDictionary?
                    s.executeAndReturnError(&err)
                }
                AppLogger.shared.log("Shutdown initiated after build completion", source: "BuildSessionManager")
            }

        default: // "nothing"
            AppLogger.shared.log("Build completion action: none", source: "BuildSessionManager")
        }
    }

    func disableInputLock() {
        guard isLocked else {
            AppLogger.shared.log("disableInputLock: already unlocked (isLocked=false)", source: "BuildSessionManager")
            return
        }
        guard let tap = eventTap else {
            // eventTap is nil but isLocked is true — clear the flag anyway
            AppLogger.shared.warning("disableInputLock: eventTap is nil, clearing isLocked flag", source: "BuildSessionManager")
            isLocked = false
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTapContext?.release()
        eventTapContext = nil
        eventTap = nil
        runLoopSource = nil
        isLocked = false
        AppLogger.shared.log("Input unlocked", source: "BuildSessionManager")
    }
}
