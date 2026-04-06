import SwiftUI


struct CirrusLabsCatalogueRow: View {
    let image: CirrusLabsImage
    let isTracked: Bool
    let downloadProgress: Double?
    let onAdd: () -> Void

    private var variantIcon: String {
        switch image.variant {
        case "Xcode":   return "hammer.circle.fill"
        case "Base":    return "shippingbox.fill"
        default:        return "apple.logo"
        }
    }

    private var variantColor: Color {
        switch image.variant {
        case "Xcode":   return .blue
        case "Base":    return .orange
        default:        return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: variantIcon)
                .font(.title3).foregroundStyle(variantColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(image.variant).fontWeight(.medium)
                    Text("·").foregroundStyle(.tertiary)
                    Text(image.imageRef
                        .components(separatedBy: "/").last?
                        .components(separatedBy: ":").first ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(image.description)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let progress = downloadProgress {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 80)
                    Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            } else if isTracked {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button("Add", action: onAdd)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
