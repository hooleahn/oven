import SwiftUI


struct BaseVMRow: View {
    let vm: VirtualMachine
    let theme: AppTheme

    private var primaryName: String {
        vm.displayName.isEmpty ? vm.name : vm.displayName
    }

    private var inferredDisplayName: String {
        // For registry VMs infer a friendly name from the image ref
        let parts = vm.name.components(separatedBy: "/")
        let last = parts.last ?? vm.name
        let clean = last.components(separatedBy: ":").first ?? last
        return clean
            .replacingOccurrences(of: "macos-", with: "")
            .replacingOccurrences(of: "-base", with: " Base")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.buildStatus.systemImage)
                .font(.title3).foregroundStyle(statusColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                // Line 1: Display name (or inferred for registry)
                Text(vm.vmSource == .registry && vm.displayName.isEmpty ? inferredDisplayName : primaryName)
                    .fontWeight(.medium).lineLimit(1)
                // Line 2: Tart name (monospaced, smaller)
                if vm.vmSource == .registry || (!vm.displayName.isEmpty && vm.displayName != vm.name) {
                    Text(vm.name)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary).lineLimit(1)
                }
                // Line 3: OS + hardware / pull date
                Text(subtitleLine).font(.caption).foregroundStyle(.secondary)
                // Line 4: Provisioning + build date (local only)
                if vm.vmSource == .local, let line2 = provisioningLine {
                    Text(line2).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if vm.buildStatus == .building {
                ProgressView().controlSize(.small)
            } else {
                Text(vm.buildStatus.label)
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitleLine: String {
        if vm.vmSource == .registry {
            if let built = vm.builtAt {
                return "Pulled " + built.formatted(date: .abbreviated, time: .omitted)
            }
            return "From registry"
        }
        var parts = ["macOS \(vm.osName.rawValue) \(vm.osVersion)"]
        parts.append("\(vm.cpuCount) CPU · \(vm.memoryGB) GB · \(vm.diskGB) GB")
        return parts.joined(separator: " · ")
    }

    private var provisioningLine: String? {
        var flags: [String] = []
        if vm.installRosetta { flags.append("Rosetta") }
        if vm.installHomebrew { flags.append("Homebrew") }
        if vm.enableSSHDaemon { flags.append("SSH") }
        if let built = vm.builtAt {
            let dateStr = built.formatted(date: .abbreviated, time: .omitted)
            if flags.isEmpty { return "Built \(dateStr)" }
            return flags.joined(separator: " · ") + " · Built \(dateStr)"
        }
        return flags.isEmpty ? nil : flags.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch vm.buildStatus {
        case .ready:    return .green
        case .building: return .purple
        case .error:    return .red
        default:        return .secondary
        }
    }
}
