import SwiftUI


struct RegistryImageRow: View {
    let image: RegistryImage
    let downloadProgress: Double?
    let onPull: () -> Void
    let onCreateVM: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image.isPulled
                  ? "externaldrive.fill.badge.checkmark"
                  : "externaldrive")
                .font(.title3)
                .foregroundStyle(image.isPulled ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(image.imageRef)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if image.isPulled {
                        Label("Pulled", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                        if let date = image.pulledAt {
                            Text("·").font(.caption2).foregroundStyle(.tertiary)
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let bytes = image.sizeBytes, bytes > 0 {
                            Text("·").font(.caption2).foregroundStyle(.tertiary)
                            Text(formatBytes(bytes))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Not pulled", systemImage: "arrow.down.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let localName = image.localName, localName != image.imageRef {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(localName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let progress = downloadProgress {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 80)
                    Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            } else if image.isPulled {
                Button(action: onCreateVM) {
                    Label("Create VM", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Menu {
                    Button("Pull again", action: onPull)
                    Divider()
                    Button("Remove from list", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("More actions")
            } else {
                Button(action: onPull) {
                    Label("Pull", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
                Menu {
                    Button("Remove from list", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("More actions")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(image.isPulled
            ? "Image: \(image.imageRef), pulled"
            : "Image: \(image.imageRef), not pulled")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
