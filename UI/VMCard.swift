import SwiftUI


struct VMCard: View {
    let vm: VirtualMachine
    let isSelected: Bool
    let onSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onEdit: () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Selectable area: thumbnail + info ───────────────────────────
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    // Thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(thumbnailColor)
                            .frame(height: 88)
                        if let wallpaper = osWallpaper,
                           let nsImg = Bundle.main.image(forResource: wallpaper) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(thumbnailOverlay)
                                )
                        } else {
                            Image(systemName: osIcon)
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        StatusDot(status: vm.status).padding(8)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.displayName.isEmpty ? vm.name : vm.displayName)
                            .font(.callout).fontWeight(.semibold).lineLimit(1)
                        Text(showsDisplayName ? vm.name : " ")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary).lineLimit(1)
                        if !vm.macOSVersion.isEmpty {
                            Text(vm.macOSVersion.replacingOccurrences(of: "macOS ", with: ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text({
                            let disk = vm.actualDiskGB.map { "\(vm.diskGB) GB max · \($0) GB used" } ?? "\(vm.diskGB) GB"
                            return "\(vm.cpuCount) CPU · \(vm.memoryGB) GB · \(disk)"
                        }())
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 4) {
                            Text("Created \(vm.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(.tertiary)
                            if let last = vm.lastStartedAt {
                                Text("·").font(.caption2).foregroundStyle(.tertiary)
                                Text("Started \(last.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .lineLimit(1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                if vm.tags.isEmpty {
                                    Color.clear
                                } else {
                                    ForEach(Array(vm.tags.prefix(4).enumerated()), id: \.offset) { _, tag in
                                        TagChip(tag: tag)
                                    }
                                }
                            }
                        }
                        .frame(height: 22)
                    }
                    .padding(10)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // ── Action buttons ───────────────────────────────────────────────
            HStack(spacing: 4) {
                if !vm.effectivelyBase {
                    // Working VM — show Start/Stop
                    if vm.status == .running || vm.status == .suspended {
                        Button(action: onStop) {
                            Image(systemName: "stop.fill").frame(width: 26, height: 26)
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(.red)
                    } else if vm.status == .stopped {
                        Button(action: onStart) {
                            Image(systemName: "play.fill").frame(width: 26, height: 26)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .help("Start")
                    } else {
                        ProgressView().controlSize(.small).frame(width: 26, height: 26)
                    }
                } else {
                    // Base VM — no start, just a badge
                    Text("Base VM")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .frame(width: 26 + 4 + 26, height: 26) // same width as two buttons
                }
                Button(action: onEdit) {
                    Image(systemName: "pencil").frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered).controlSize(.small).help("Edit")
                Button(action: onClone) {
                    Image(systemName: "doc.on.doc").frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered).controlSize(.small).help("Clone")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered).controlSize(.small).help("Delete")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .zIndex(1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 2 : 0.5)
        )
        .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 6 : 2)

        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var osWallpaper: String? {
        let v = vm.macOSVersion.lowercased()
        if v.contains("tahoe")    { return "wallpaper-tahoe" }
        if v.contains("sequoia")  { return "wallpaper-sequoia" }
        if v.contains("sonoma")   { return "wallpaper-sonoma" }
        if v.contains("ventura")  { return "wallpaper-ventura" }
        if v.contains("monterey") { return "wallpaper-monterey" }
        return nil
        // Note: loaded via Bundle.main.image(forResource:) from Resources/
    }

    private var osIcon: String {
        let v = vm.macOSVersion.lowercased()
        if v.contains("sequoia") { return "apple.logo" }
        if v.contains("sonoma")  { return "apple.logo" }
        if v.contains("ventura") { return "apple.logo" }
        return "desktopcomputer"
    }

    /// Tint overlay on wallpaper when VM is running/suspended/building
    private var thumbnailOverlay: Color {
        switch vm.status {
        case .running:   return Color.accentColor.opacity(0.35)
        case .suspended: return .orange.opacity(0.3)
        case .building:  return .purple.opacity(0.3)
        default:         return .clear
        }
    }

    private var osVersionShort: String {
        vm.macOSVersion
            .replacingOccurrences(of: "macOS ", with: "")
            .replacingOccurrences(of: "macOS", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var thumbnailColor: Color {
        switch vm.status {
        case .running:   return Color.accentColor.opacity(0.75)
        case .suspended: return .orange.opacity(0.7)
        case .building:  return .purple.opacity(0.6)
        default:         return Color.primary.opacity(0.18)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !vm.macOSVersion.isEmpty {
            parts.append(vm.macOSVersion.replacingOccurrences(of: "macOS ", with: ""))
        }
        parts.append("\(vm.cpuCount) CPU · \(vm.memoryGB) GB")
        return parts.joined(separator: " · ")
    }
    
    // Show display name below title if it differs from the technical name
    private var showsDisplayName: Bool {
        !vm.displayName.isEmpty && vm.displayName != vm.name
    }
}
