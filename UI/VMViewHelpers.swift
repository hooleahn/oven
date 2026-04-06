import SwiftUI

// MARK: - Status pill

struct StatusPill: View {
    let status: VirtualMachine.Status

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(status.label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(bgColor, in: Capsule())
        .accessibilityLabel("Status: \(status.label)")
    }

    private var dotColor: Color {
        switch status {
        case .running:   return .green
        case .suspended: return .orange
        case .building:  return .purple
        case .error:     return .red
        default:         return .gray
        }
    }
    private var bgColor: Color {
        switch status {
        case .running:   return .green.opacity(0.12)
        case .suspended: return .orange.opacity(0.12)
        case .building:  return .purple.opacity(0.12)
        case .error:     return .red.opacity(0.12)
        default:         return Color.primary.opacity(0.07)
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
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        Divider().padding(.leading, 14)
    }
}


struct StatusDot: View {
    let status: VirtualMachine.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))
            .accessibilityLabel(status.label)
            .accessibilityHidden(false)
    }

    private var color: Color {
        switch status {
        case .running:   return .green
        case .suspended: return .orange
        case .building:  return .purple
        case .error:     return .red
        default:         return .gray.opacity(0.5)
        }
    }
}
