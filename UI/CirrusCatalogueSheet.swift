import SwiftUI


struct CirrusCatalogueSheet: View {
    let trackedRefs: Set<String>
    let activeDownloads: [String: Double]
    let onAdd: (CirrusLabsImage) -> Void
    @Environment(\.dismiss) private var dismiss

    private let osOrder = [
        "macOS 26 Tahoe", "macOS 15 Sequoia",
        "macOS 14 Sonoma", "macOS 13 Ventura", "macOS 12 Monterey"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cirrus Labs Images").font(.headline)
                    Text("Official public macOS images from ghcr.io/cirruslabs")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16).background(.bar)
            Divider()

            let grouped = Dictionary(grouping: RegistryService.cirrusLabsCatalogue, by: \.os)
            List {
                ForEach(osOrder, id: \.self) { os in
                    if let imgs = grouped[os] {
                        Section(os) {
                            ForEach(imgs) { img in
                                CirrusLabsCatalogueRow(
                                    image: img,
                                    isTracked: trackedRefs.contains(img.imageRef),
                                    downloadProgress: activeDownloads[img.imageRef],
                                    onAdd: { onAdd(img); dismiss() }
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480)
    }
}
