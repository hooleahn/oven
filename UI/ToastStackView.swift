import SwiftUI

// MARK: - ToastStackView

/// Renders the global error/warning toast stack at the top-centre of its container.
/// Drop this inside a `ZStack(alignment: .top)` over the content you want to overlay.
struct ToastStackView: View {

    @AppStorage("toast.disabled") private var toastsDisabled = false

    private var center: ToastCenter { ToastCenter.shared }

    var body: some View {
        if !toastsDisabled {
            GeometryReader { geo in
                let w = min(geo.size.width, min(720, max(360, geo.size.width * 0.65)))
                VStack(spacing: 6) {
                    ForEach(center.toasts) { toast in
                        ToastCapsule(toast: toast)
                            .transition(
                                .move(edge: .top).combined(with: .opacity)
                            )
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .frame(width: w)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .animation(.snappy, value: center.toasts.map(\.id))
        }
    }
}

// MARK: - ToastCapsule

private struct ToastCapsule: View {

    let toast: ToastCenter.Toast
    @Environment(\.openURL) private var openURL
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 8) {
            // Severity icon
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.callout.weight(.semibold))

            // Source label + message
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.source)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(toast.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { withAnimation(.snappy) { isExpanded.toggle() } }
            }

            Spacer(minLength: 0)

            // "Details" deep-link button
            if let deepLink = toast.deepLink {
                Button("Details") {
                    deepLink()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.accent)
            }

            // Copy button (errors only)
            if toast.severity == .error {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString("[\(toast.source)] \(toast.message)", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy message")
            }

            // Dismiss button
            Button {
                withAnimation(.snappy) {
                    ToastCenter.shared.dismiss(id: toast.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(iconColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private var iconName: String {
        switch toast.severity {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch toast.severity {
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
