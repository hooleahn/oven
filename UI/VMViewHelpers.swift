import SwiftUI

// MARK: - Status pill (used only in detail pane header)

struct StatusPill: View {
    let status: VirtualMachine.Status

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(pillColor))
            .padding(.horizontal, Spacing.sm + 2) // 10 pt
            .padding(.vertical, Spacing.xs)
            .background(reduceTransparency ? pillColor : Color.clear, in: Capsule())
            .overlay(
                Capsule().strokeBorder(pillColor, lineWidth: 0.5)
            )
            .accessibilityLabel("Status: \(status.label)")
    }

    private var pillColor: Color {
        switch status {
        case .running:   return .green
        case .suspended: return .secondary
        case .building:  return .accentColor
        case .error:     return .red
        default:         return .secondary.opacity(0.5)
        }
    }
}

// MARK: - Detail section/row helpers

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.lg - 2) // 14 pt
                .padding(.top, Spacing.lg - 2)
                .padding(.bottom, Spacing.xs + 2)    // 6 pt
            content()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var copyable: Bool = false
    @State private var copied = false

    init(_ label: String, _ value: String, monospaced: Bool = false, copyable: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
        self.copyable = copyable
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(monospaced
                      ? .system(.callout, design: .monospaced)
                      : .callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
        .padding(.horizontal, Spacing.lg - 2) // 14 pt
        .padding(.vertical, 5)
        Divider().padding(.leading, Spacing.lg - 2)
    }
}


struct StatusDot: View {
    let status: VirtualMachine.Status

    var body: some View {
        ZStack {
            if status == .suspended {
                // Receding: secondary-colored pause icon at 7 pt, no filled circle
                Image(systemName: "pause.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityLabel(status.label)
        .accessibilityHidden(false)
    }

    private var dotColor: Color {
        switch status {
        case .running:   return .green
        case .building:  return .accentColor
        case .error:     return .red
        default:         return Color.secondary.opacity(0.5)
        }
    }
}
