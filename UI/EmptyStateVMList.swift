import SwiftUI

// MARK: - EmptyStateVMList

struct EmptyStateVMList: View {
    @EnvironmentObject var baseVMStore: BaseVMStore
    @EnvironmentObject var appState: AppState

    var onClone: (VirtualMachine) -> Void
    var onNewVM: () -> Void

    @State private var showHelp = false
    @State private var showCirrusCatalogue = false

    private var readyBases: [VirtualMachine] {
        baseVMStore.baseVMs.filter { $0.buildStatus == .ready }
    }

    var body: some View {
        EmptyStateView(
            "No Virtual Machines",
            systemImage: "desktopcomputer",
            description: "VMs are clones of a Base VM. Pick a base to create your first VM."
        ) {
            if readyBases.isEmpty {
                // No bases yet — guide user to get one first
                VStack(spacing: 10) {
                    Text("First, you need a Base VM")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Browse Base Images") {
                        showCirrusCatalogue = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Show inline list of ready bases with Clone buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a Base VM to clone:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        ForEach(readyBases.prefix(5)) { base in
                            HStack {
                                Image(systemName: "cpu")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(base.displayName.isEmpty ? base.name : base.displayName)
                                    .font(.callout)
                                Spacer()
                                Button("Clone") {
                                    onClone(base)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .frame(maxWidth: 380)
                }
            }
        } content: {
            // Tertiary "What are Base VMs?" help link
            Button {
                showHelp = true
            } label: {
                Text("What are Base VMs?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp) {
                baseVMHelpPopover
            }
        }
        .sheet(isPresented: $showCirrusCatalogue) {
            CirrusCatalogueSheet(
                trackedRefs: [],
                activeDownloads: [:]
            ) { _ in
                showCirrusCatalogue = false
            }
        }
    }

    private var baseVMHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are Base VMs?")
                .font(.headline)

            // 3-step explainer
            VStack(alignment: .leading, spacing: 12) {
                HelpStep(number: "1", title: "Build or download a Base VM",
                         detail: "A Base VM is a gold image — a fully configured macOS VM your org manages.")
                HelpStep(number: "2", title: "Clone it into Working VMs",
                         detail: "Working VMs are fast, lightweight clones. Each developer or CI job gets their own.")
                HelpStep(number: "3", title: "Rebuild anytime",
                         detail: "When you update your base image, re-clone to distribute fresh VMs instantly.")
            }

            Text(
                "Base VMs act as your organization's gold image. They're built once with Packer (or downloaded from a registry), then cloned on demand. Cloning is near-instant because Oven and Tart use copy-on-write snapshots under the hood — no duplication needed. Keep your base lean and well-configured, and all derived VMs inherit those properties automatically."
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

// MARK: - HelpStep

private struct HelpStep: View {
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
