import Foundation

// MARK: - PushManager

/// Global manager for push-to-registry operations.
/// Tracks in-flight pushes across the entire app so multiple views
/// can observe progress without duplicating push logic.
@MainActor
@Observable
final class PushManager {

    /// Maps baseVM.name → progress (0…1) for every active push.
    var active: [String: Double] = [:]

    /// Maps baseVM.name → human-readable error string for the most recent failure.
    var errors: [String: String] = [:]

    // MARK: - Public API

    /// Start a push for `baseVM` to `imageRef`.
    /// - If a push for this VM is already in flight the call is a no-op.
    func push(baseVM: VirtualMachine, to imageRef: String,
              credentials: [RegistryCredential], tartPath: String) async {
        guard active[baseVM.name] == nil else { return }

        let host = imageRef.components(separatedBy: "/").first ?? ""
        let cred = credentials.first(where: { $0.registry == host })

        active[baseVM.name] = 0.0
        errors[baseVM.name] = nil

        var errorLines: [String] = []
        AppLogger.shared.log("Pushing \(baseVM.name) → \(imageRef)", source: "PushManager")

        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartPath,
                                  registryUsername: cred?.username,
                                  registryPassword: cred?.password)
        let stream = await tartSvc.push(name: baseVM.name, to: imageRef)

        for await event in stream {
            switch event {
            case .stdout(let line):
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("Error:") { errorLines.append(t) }
                if line.contains("%") {
                    let digits = line.filter { $0.isNumber || $0 == "." }
                    if let pct = Double(digits) {
                        active[baseVM.name] = min(pct / 100.0, 1.0)
                    }
                }
                AppLogger.shared.log(line, source: "Push")

            case .stderr(let line):
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { errorLines.append(t) }
                AppLogger.shared.log(line, source: "Push")

            case .exit(let code):
                active[baseVM.name] = nil
                if code == 0 {
                    AppLogger.shared.success("Push complete: \(imageRef)", source: "PushManager")
                } else {
                    let raw = errorLines.joined(separator: "\n")
                    AppLogger.shared.error("Push failed (exit \(code)): \(raw)", source: "PushManager")
                    errors[baseVM.name] = parseTartError(raw)
                        ?? (raw.isEmpty ? "Push failed (exit \(code))" : raw)
                }
            }
        }
    }

    /// Clear the stored error for a VM (e.g. after the user dismisses the alert).
    func clearError(for vmName: String) {
        errors[vmName] = nil
    }
}
