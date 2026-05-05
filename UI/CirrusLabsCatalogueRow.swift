import SwiftUI

struct CirrusLabsCatalogueRow: View {
    let image: CirrusLabsImage
    let trackedRefs: Set<String>
    let activeDownloads: [String: Double]
    let onAdd: (String) -> Void

    @State private var selectedTag: String

    init(image: CirrusLabsImage, trackedRefs: Set<String>, activeDownloads: [String: Double],
         onAdd: @escaping (String) -> Void) {
        self.image = image
        self.trackedRefs = trackedRefs
        self.activeDownloads = activeDownloads
        self.onAdd = onAdd
        _selectedTag = State(initialValue: image.defaultTag)
    }

    private var selectedRef: String { image.ref(tag: selectedTag) }
    private var isTracked: Bool { trackedRefs.contains(selectedRef) }
    private var downloadProgress: Double? { activeDownloads[selectedRef] }

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
                    if image.tags.count > 1 {
                        Picker("", selection: $selectedTag) {
                            ForEach(image.tags, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.system(.caption, design: .monospaced))
                    } else {
                        Text(image.imageRef
                            .components(separatedBy: "/").last?
                            .components(separatedBy: ":").first ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
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
                Button("Add") { onAdd(selectedRef) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
