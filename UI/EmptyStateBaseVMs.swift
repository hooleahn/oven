import SwiftUI

// MARK: - EmptyStateBaseVMs

struct EmptyStateBaseVMs: View {
    @Environment(AppTheme.self) private var theme

    var onBrowsePrebuilt: () -> Void
    var onBuildFromIPSW: () -> Void

    @State private var showHelp = false

    var body: some View {
        EmptyStateView(
            theme.funModeEnabled ? "No Recipes Yet" : "No Base VMs",
            systemImage: theme.baseVMIcon,
            description: theme.funModeEnabled
                ? "Recipes are your org's gold images. Download a prebuilt one or bake from scratch."
                : "Base VMs are your organization's gold images. Download a prebuilt one or build from IPSW."
        ) {
            // Two primary actions side-by-side
            HStack(spacing: 10) {
                Button {
                    onBrowsePrebuilt()
                } label: {
                    Label("Browse Prebuilt Images", systemImage: "building.columns")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onBuildFromIPSW()
                } label: {
                    Label("Build from IPSW", systemImage: "arrow.down.to.line.compact")
                }
                .buttonStyle(.bordered)
            }
        } content: {
            VStack(spacing: 10) {
                // Help link
                Button {
                    showHelp = true
                } label: {
                    Text("What is a Base VM?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHelp) {
                    baseVMHelpPopover
                }
            }
        }
    }

    private var baseVMHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is a Base VM?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HelpStepSmall(number: "1", title: "Build or download once",
                              detail: "A Base VM is a fully configured macOS image — your org's gold standard.")
                HelpStepSmall(number: "2", title: "Clone instantly",
                              detail: "Spin up Working VMs from any base using copy-on-write snapshots.")
                HelpStepSmall(number: "3", title: "Update and redistribute",
                              detail: "Rebuild the base to push changes to every derived VM.")
            }

            Text(
                "Base VMs are immutable gold images managed by your team. Build them with Packer templates or pull them from a container registry. Once ready, cloning is near-instant — Tart's copy-on-write filesystem means no data duplication."
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

// MARK: - HelpStepSmall (private helper)

private struct HelpStepSmall: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
