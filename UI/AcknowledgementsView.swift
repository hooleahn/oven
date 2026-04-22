import SwiftUI

// MARK: - AcknowledgementsView

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Acknowledgements")
                    .font(.title2.bold())
                Text("Oven is built on the shoulders of great open-source work.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)
            .padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "App Icon")
                    AckRow(
                        name: "Oven icon",
                        author: "Flaticon",
                        license: "Flaticon License",
                        url: "https://www.flaticon.com/free-icons/oven",
                        note: "Free for personal and commercial use with attribution."
                    )

                    SectionHeader(title: "Runtime Tools")
                    AckRow(
                        name: "tart",
                        author: "Cirrus Labs",
                        license: "Fair Source License v0.9",
                        url: "https://github.com/cirruslabs/tart",
                        note: "Virtualization tool for running macOS and Linux VMs on Apple Silicon."
                    )
                    AckRow(
                        name: "packer",
                        author: "HashiCorp / IBM",
                        license: "Business Source License 1.1",
                        url: "https://github.com/hashicorp/packer",
                        note: "Tool for building automated machine images."
                    )
                    AckRow(
                        name: "packer-plugin-tart",
                        author: "Cirrus Labs",
                        license: "Mozilla Public License 2.0",
                        url: "https://github.com/cirruslabs/packer-plugin-tart",
                        note: "Packer plugin that adds support for tart VMs."
                    )
                    AckRow(
                        name: "mist-cli",
                        author: "Nindi Gill",
                        license: "MIT License",
                        url: "https://github.com/ninxsoft/mist-cli",
                        note: "Command-line tool to download macOS Firmwares and Installers."
                    )
                    AckRow(
                        name: "jq",
                        author: "Stephen Dolan and contributors",
                        license: "MIT License",
                        url: "https://github.com/jqlang/jq",
                        note: "Lightweight and flexible command-line JSON processor."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

private struct AckRow: View {
    let name: String
    let author: String
    let license: String
    let url: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.body.bold())
                Text("·")
                    .foregroundStyle(.tertiary)
                Link(url, destination: URL(string: url)!)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("–")
                    .foregroundStyle(.tertiary)
                LicenseBadge(license: license)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)

        Divider()
            .opacity(0.5)
    }
}

private struct LicenseBadge: View {
    let license: String

    private var color: Color {
        switch license {
        case "MIT License":              return .green
        case "Mozilla Public License 2.0": return .blue
        case "Flaticon License":         return .purple
        default:                         return .orange
        }
    }

    /// Licenses that are not standard OSI-approved open-source licenses.
    private var isNonStandard: Bool {
        license == "Fair Source License v0.9" || license == "Business Source License 1.1"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(license)
                .font(.caption2.bold())
                .foregroundStyle(color)
            if isNonStandard {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("This license is not an OSI-approved open-source license and has commercial use restrictions.")
            }
        }
    }
}
