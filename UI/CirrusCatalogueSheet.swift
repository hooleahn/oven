import SwiftUI

struct CirrusCatalogueSheet: View {
    let trackedRefs: Set<String>
    let activeDownloads: [String: Double]
    let token: String?
    let onAdd: (String) -> Void  // imageRef with selected tag
    @Environment(\.dismiss) private var dismiss

    @State private var images: [CirrusLabsImage] = RegistryService.cirrusLabsCatalogue
    @State private var isLoading = false
    @State private var fetchFailed = false

    private let osOrder = [
        "macOS 27 Golden Gate", "macOS 26 Tahoe", "macOS 15 Sequoia",
        "macOS 14 Sonoma", "macOS 13 Ventura", "macOS 12 Monterey"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cirrus Labs Images").font(.headline)
                    Group {
                        if isLoading {
                            Text("Fetching live catalogue from GitHub…")
                        } else if fetchFailed {
                            Text("Showing cached list — live fetch failed.")
                                .foregroundStyle(.orange)
                        } else if token != nil {
                            Text("Live catalogue · ghcr.io/cirruslabs")
                        } else {
                            Text("Official public macOS images · ghcr.io/cirruslabs")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small).padding(.trailing, 6)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16).background(.bar)
            Divider()

            let grouped = Dictionary(grouping: images, by: \.os)
            let knownSet = Set(osOrder)
            let extraOSes = images.map(\.os)
                .filter { !knownSet.contains($0) }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

            List {
                ForEach(osOrder, id: \.self) { os in
                    if let imgs = grouped[os] {
                        Section(os) {
                            ForEach(imgs) { img in
                                CirrusLabsCatalogueRow(
                                    image: img,
                                    trackedRefs: trackedRefs,
                                    activeDownloads: activeDownloads,
                                    onAdd: { imageRef in onAdd(imageRef); dismiss() }
                                )
                            }
                        }
                    }
                }
                ForEach(extraOSes, id: \.self) { os in
                    if let imgs = grouped[os] {
                        Section(os) {
                            ForEach(imgs) { img in
                                CirrusLabsCatalogueRow(
                                    image: img,
                                    trackedRefs: trackedRefs,
                                    activeDownloads: activeDownloads,
                                    onAdd: { imageRef in onAdd(imageRef); dismiss() }
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480)
        .task {
            guard let token else { return }
            isLoading = true
            do {
                images = try await RegistryService.fetchCirrusCatalogue(token: token)
            } catch {
                fetchFailed = true
            }
            isLoading = false
        }
    }
}
