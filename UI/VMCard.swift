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

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Selectable area: thumbnail + info ───────────────────────────
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    // Thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.thumbnail)
                            .fill(thumbnailColor)
                            .frame(height: 140)
                        if let wallpaper = osWallpaper,
                           let nsImg = Bundle.main.image(forResource: wallpaper) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.thumbnail)
                                        .fill(thumbnailOverlay)
                                )
                                .overlay(
                                    // Gradient overlay on bottom 40% for text legibility
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .clear, location: 0.6),
                                            .init(color: .black.opacity(0.7), location: 1.0)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail))
                                )
                        } else {
                            Image(systemName: osIcon)
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        StatusDot(status: vm.status).padding(Spacing.sm)
                    }

                    // Info — frame(maxWidth: .infinity) ensures the full card width is
                    // hittable, not just the area directly beneath left-aligned text.
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(vm.displayName.isEmpty ? vm.name : vm.displayName)
                            .font(.cardTitle).lineLimit(1)
                        Text(showsDisplayName ? vm.name : " ")
                            .font(.cardMono)
                            .foregroundStyle(.tertiary).lineLimit(1)
                        if !vm.osVersion.isEmpty {
                            Text("\(vm.osName.rawValue) \(vm.osVersion)")
                                .font(.cardSubtitle).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if vm.osName == .unknown && vm.osVersion.isEmpty {
                            Text("Unknown OS")
                                .font(.cardSubtitle).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text("\(vm.cpuCount) CPU · \(vm.memoryGB) GB RAM · \(vm.diskGB) GB SSD")
                        .font(.cardSubtitle).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: Spacing.xs) {
                            Text("Created \(vm.createdAt.formatted(date: .numeric, time: .omitted))")
                                .font(.caption2).foregroundStyle(.tertiary)
                            if let last = vm.lastStartedAt {
                                Text("·").font(.caption2).foregroundStyle(.tertiary)
                                Text("Started \(last.formatted(date: .numeric, time: .omitted))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .lineLimit(1)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.xs) {
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
                        // Prevent the ScrollView from swallowing taps that should select the card
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md - 2) // ≈ 10 pt, matching previous value
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Action buttons ───────────────────────────────────────────────
            HStack(spacing: Spacing.xs) {
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
                        .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                        .background(.quaternary, in: Capsule())
                        .frame(width: 26 + 4 + 26, height: 26)
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
            .padding(.horizontal, Spacing.md - 2) // ≈ 10 pt
            .padding(.bottom, Spacing.md - 2)
            .zIndex(1)
        }
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card))
        .cardStyle(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var osWallpaper: String? {
        let v = vm.osName.rawValue.lowercased()
        if v.contains("tahoe")    { return "wallpaper-tahoe" }
        if v.contains("sequoia")  { return "wallpaper-sequoia" }
        if v.contains("sonoma")   { return "wallpaper-sonoma" }
        if v.contains("ventura")  { return "wallpaper-ventura" }
        if v.contains("monterey") { return "wallpaper-monterey" }
        return nil
    }

    private var osIcon: String {
        let v = vm.osName.rawValue.lowercased()
        if v.contains("sequoia") { return "apple.logo" }
        if v.contains("sonoma")  { return "apple.logo" }
        if v.contains("ventura") { return "apple.logo" }
        return "desktopcomputer"
    }

    /// Tint overlay on wallpaper when VM is running/suspended/building
    private var thumbnailOverlay: Color {
        switch vm.status {
        case .running:   return Color.vmRunning.opacity(0.35)
        case .suspended: return .orange.opacity(0.3)
        case .building:  return Color.vmBuilding.opacity(0.3)
        default:         return .clear
        }
    }

    private var thumbnailColor: Color {
        switch vm.status {
        case .running:   return Color.vmRunning.opacity(0.75)
        case .suspended: return .orange.opacity(0.7)
        case .building:  return Color.vmBuilding.opacity(0.6)
        default:         return Color.primary.opacity(0.18)
        }
    }

    private var showsDisplayName: Bool {
        !vm.displayName.isEmpty && vm.displayName != vm.name
    }
}
