import SwiftUI

// MARK: - Triangle shape for error indicator

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Status pill (used only in detail pane header)

struct StatusPill: View {
    let status: VirtualMachine.Status

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(pillColor)
            .padding(.horizontal, Spacing.sm + 2) // 10 pt
            .padding(.vertical, Spacing.xs)
            .background(pillColor.opacity(reduceTransparency ? 1 : 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(pillColor.opacity(0.25), lineWidth: 0.5))
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
                .font(.caption2.weight(.semibold))
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
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .contentShape(Rectangle().inset(by: -6))
                .help("Copy to clipboard")
                .accessibilityLabel("Copy \(label) to clipboard")
                .accessibilityHint("Copies the value \(value)")
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
            switch status {
            case .running:
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
            case .stopped:
                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 10, height: 10)
            case .error:
                TriangleShape()
                    .fill(Color.red)
                    .frame(width: 10, height: 9)
            case .suspended:
                Image(systemName: "pause.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)
            case .building:
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 9, height: 9)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityLabel("Status: \(status.label)")
        .accessibilityHidden(false)
    }
}
