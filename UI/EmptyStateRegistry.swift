import SwiftUI

// MARK: - EmptyStateRegistry

struct EmptyStateRegistry: View {
    let registry: String
    var onBrowseCirrus: () -> Void
    var onAddImage: () -> Void

    @State private var showHelp = false

    var body: some View {
        EmptyStateView(
            "No Images on \(registryShortName)",
            systemImage: "externaldrive.connected.to.line.below",
            description: "Track OCI images to pull them as Base VMs or Working VMs. Add an image reference below, or browse the Cirrus Labs catalogue."
        ) {
            HStack(spacing: 10) {
                Button {
                    onBrowseCirrus()
                } label: {
                    Label("Browse Cirrus Labs", systemImage: "building.columns")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onAddImage()
                } label: {
                    Label("Add Image Reference", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        } content: {
            Button {
                showHelp = true
            } label: {
                Text("How does the registry work?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp) {
                registryHelpPopover
            }
        }
    }

    private var registryShortName: String {
        switch registry {
        case "ghcr.io":   return "GitHub Container Registry"
        case "docker.io": return "Docker Hub"
        default:          return registry
        }
    }

    private var registryHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How does the registry work?")
                .font(.headline)

            Text(
                "Oven tracks OCI image references (like `ghcr.io/org/image:tag`) and lets you pull them directly as Base VMs or Working VMs. Use the Cirrus Labs catalogue to discover official macOS images, or paste any public or private OCI reference in the bar at the bottom. Credentials for private registries can be added in Preferences."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Link("Read the docs", destination: URL(string: "https://tart.run/quick-start/")!)
                .font(.callout)
        }
        .padding(16)
        .frame(width: 320)
    }
}
