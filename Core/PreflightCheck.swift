import Foundation
import Network
import IOKit.ps

// MARK: - PreflightResult

struct PreflightResult {
    var passed: Bool { failures.isEmpty }
    var failures: [PreflightFailure] = []
    var warnings: [String] = []
}

struct PreflightFailure: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isFatal: Bool   // false = warn only, true = block build
}

// MARK: - PreflightCheck

@MainActor
final class PreflightCheck {

    static let shared = PreflightCheck()
    private init() {}

    // Minimum free space required in each storage root (bytes)
    static let minimumFreeSpaceBytes: Int64 = 60 * 1_073_741_824  // 60 GB

    // Minimum battery level (%) to allow building on battery power
    static let minimumBatteryPercent: Double = 80.0

    // MARK: - Run all checks

    func runAll(baseVM: VirtualMachine, ipswAlreadyLocal: Bool) async -> PreflightResult {
        var result = PreflightResult()

        checkPowerSource(into: &result)
        checkDiskSpace(baseVM: baseVM, into: &result)
        if !ipswAlreadyLocal {
            await checkNetworkReachability(into: &result)
        }
        await checkPackerPluginVersion(into: &result)
        checkOSVersion(into: &result)

        return result
    }

    // MARK: - 1. Power source

    func checkPowerSource(into result: inout PreflightResult) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            // No battery info (desktop Mac) — always fine
            return
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let isOnAC     = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let capacity   = (info[kIOPSCurrentCapacityKey] as? Double) ?? 100
            let threshold  = UserDefaults.standard.double(forKey: "batteryThresholdPct")
            let minBattery = threshold > 0 ? threshold : Self.minimumBatteryPercent

            if !isOnAC && !isCharging {
                if capacity < minBattery {
                    result.failures.append(PreflightFailure(
                        title: "Low battery (\(Int(capacity))%)",
                        detail: "The computer is on battery power at \(Int(capacity))% charge. "
                              + "A Base VM build takes 30–90 minutes and may drain the battery before completing. "
                              + "Connect to power or lower the battery threshold in Preferences.",
                        isFatal: true
                    ))
                } else {
                    result.warnings.append("Running on battery (\(Int(capacity))% charge). Connect to power for a long build.")
                }
            }
        }
    }

    // MARK: - 2. Disk space

    func checkDiskSpace(baseVM: VirtualMachine, into result: inout PreflightResult) {
        let settings = AppSettings.load()
        let roots: [(String, URL)] = [
            ("IPSW storage",  settings.ipswStorageRoot),
            ("VM storage",    settings.vmStorageRoot),
            ("Templates dir", settings.packerTemplatesRoot),
        ]
        for (label, url) in roots {
            guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
                  let free  = attrs[.systemFreeSize] as? Int64 else { continue }
            if free < Self.minimumFreeSpaceBytes {
                let freeGB = Double(free) / 1_073_741_824
                let needGB = Double(Self.minimumFreeSpaceBytes) / 1_073_741_824
                result.failures.append(PreflightFailure(
                    title: "Low disk space in \(label)",
                    detail: String(format: "%.1f GB free, %.0f GB recommended. "
                                 + "Free up space or change the storage location in Preferences.",
                                   freeGB, needGB),
                    isFatal: true
                ))
            }
        }
    }

    // MARK: - 3. Network reachability

    func checkNetworkReachability(into result: inout PreflightResult) async {
        // Use an actor-isolated wrapper to safely coordinate the one-shot continuation
        // NWPathMonitor has no async API; wrap in a checked continuation with a
        // Task-based 3-second timeout so the main async context isn't blocked.
        let satisfied = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    let monitor = NWPathMonitor()
                    nonisolated(unsafe) var fired = false
                    let fire: (Bool) -> Void = { value in
                        guard !fired else { return }
                        fired = true
                        monitor.cancel()
                        cont.resume(returning: value)
                    }
                    // NWPathMonitor requires a DispatchQueue — no Swift Concurrency equivalent
                    monitor.pathUpdateHandler = { path in fire(path.status == .satisfied) }
                    monitor.start(queue: DispatchQueue(label: "oven.preflight.network",
                                                       qos: .utility))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return true  // timeout → assume OK
            }
            let result = await group.next() ?? true
            group.cancelAll()
            return result
        }
        if !satisfied {
            result.failures.append(PreflightFailure(
                title: "No network connection",
                detail: "An internet connection is required to download the macOS IPSW via mist-cli. "
                      + "Connect to a network or select a locally downloaded IPSW.",
                isFatal: true
            ))
        }
    }

    // MARK: - 4. Packer plugin version

    func checkPackerPluginVersion(into result: inout PreflightResult) async {
        let depsRoot   = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps")
        let packerPath = depsRoot.appendingPathComponent("packer").path
        let pluginDir  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path

        guard FileManager.default.fileExists(atPath: packerPath) else { return }

        do {
            let runner = ProcessRunner()
            let (stdout, _) = try await runner.run(
                packerPath,
                arguments: ["plugins", "installed"],
                environment: ["PACKER_PLUGIN_PATH": pluginDir]
            )
            // Output lines like: github.com/cirruslabs/tart v1.20.1
            let versionLine = stdout.split(separator: "\n")
                .first { $0.contains("cirruslabs/tart") }
            if let line = versionLine,
               let vStr = line.split(separator: " ").last,
               vStr.hasPrefix("v") {
                let version = String(vStr.dropFirst()) // e.g. "1.20.1"
                let parts   = version.split(separator: ".").compactMap { Int($0) }
                let major   = parts.count > 0 ? parts[0] : 0
                let minor   = parts.count > 1 ? parts[1] : 0
                let minMajor = 1; let minMinor = 20
                if (major, minor) < (minMajor, minMinor) {
                    result.failures.append(PreflightFailure(
                        title: "Packer plugin too old (v\(version))",
                        detail: "The tart packer plugin must be v\(minMajor).\(minMinor).0 or later for the `headless` field to work. "
                              + "Go to Preferences and reinstall dependencies to update.",
                        isFatal: true
                    ))
                }
            }
        } catch {
            // If we can't query the version, let the build proceed and fail with a better message
            result.warnings.append("Could not verify packer-plugin-tart version: \(error.localizedDescription)")
        }
    }

    // MARK: - 5. macOS version

    func checkOSVersion(into result: inout PreflightResult) {
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        // tart requires macOS 13+, our app targets 14+
        if ver.majorVersion < 13 {
            result.failures.append(PreflightFailure(
                title: "macOS \(ver.majorVersion).\(ver.minorVersion) not supported",
                detail: "Oven requires macOS 13 Ventura or later. tart requires Apple Silicon with macOS 13+.",
                isFatal: true
            ))
        }
    }

    // MARK: - Template validation

    func validateTemplate(templateName: String, varsName: String) async -> Result<Void, PreflightError> {
        let depsRoot   = AppSettings.defaultLocalStorageRoot.appendingPathComponent("deps")
        let packerPath = depsRoot.appendingPathComponent("packer").path
        let pluginDir  = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart").path
        let templatesRoot = AppSettings.load().packerTemplatesRoot
        let templateURL   = templatesRoot.appendingPathComponent(templateName)
        let varsURL       = templatesRoot.appendingPathComponent(varsName)

        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            return .failure(.message("Template file not found: \(templateURL.lastPathComponent)"))
        }
        guard FileManager.default.fileExists(atPath: varsURL.path) else {
            return .failure(.message("Vars file not found: \(varsURL.lastPathComponent)"))
        }

        do {
            let runner = ProcessRunner()
            let parentEnv = ProcessInfo.processInfo.environment
            let (stdout, stderr) = try await runner.run(
                packerPath,
                arguments: ["validate", "-var-file=\(varsURL.path)", templateURL.path],
                environment: [
                    "PACKER_PLUGIN_PATH": pluginDir,
                    "PATH":   "\(depsRoot.path):/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME":   parentEnv["HOME"]   ?? NSHomeDirectory(),
                    "TMPDIR": parentEnv["TMPDIR"] ?? "/tmp",
                    "OVEN_VM_PASSWORD": "preflight-check",
                ]
            )
            let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            if !output.isEmpty {
                AppLogger.shared.log("[validate] \(output)", source: "PreflightCheck")
            }
            return .success(())
        } catch let error as ProcessError {
            // Extract the actual packer error message from the ProcessError
            let msg: String
            switch error {
            case .nonZeroExit(_, let stderr): msg = stderr.isEmpty ? error.localizedDescription : stderr
            default: msg = error.localizedDescription
            }
            AppLogger.shared.error("Template validation failed: \(msg)", source: "PreflightCheck")
            return .failure(.message(msg))
        } catch {
            AppLogger.shared.error("Template validation error: \(error.localizedDescription)", source: "PreflightCheck")
            return .failure(.message(error.localizedDescription))
        }
    }
}

// MARK: - PreflightError

enum PreflightError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}
