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
                            Text("·").foregroundStyle(.secondary)
                            Text("on " + date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not pulled").font(.caption).foregroundStyle(.secondary)
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
                Button("Create VM", action: onCreateVM)
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Menu {
                    Button("Remove from list", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("Pull", action: onPull)
                    .buttonStyle(.bordered).controlSize(.small)
                Menu {
                    Button("Remove from list", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
