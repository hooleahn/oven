import SwiftUI

// MARK: - RegistryPullDestination

enum RegistryPullDestination {
    case baseVM
    case virtualMachine
    case justPull
}

// MARK: - PullDestinationSheet

struct PullDestinationSheet: View {
    let image: RegistryImage
    var initialOSVersion: String = ""
    let onChoose: (RegistryPullDestination, String, String) -> Void  // destination, osVersion, displayName
    @Environment(\.dismiss) private var dismiss
    @State private var osVersion: String = ""
    @State private var displayName: String = ""

    private var imageName: String {
        image.imageRef.components(separatedBy: "/").last ?? image.imageRef
    }

    /// Preview of the auto-generated tart name — the real name is finalised
    /// (with a uniqueness suffix if needed) when the pull actually starts.
    private var placeholderName: String {
        let ver = osVersion.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmm"
        return "oci-macos-\(ver.isEmpty ? "unknown" : ver)-\(formatter.string(from: .now))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Use \"\(imageName)\" as…").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding(16).background(.bar)
            Divider()
            VStack(spacing: 12) {
                Text("How do you want to use this pulled image?")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Section {
                    LabeledContent("OS version") {
                        TextField("", text: $osVersion,
                                  prompt: Text("e.g. 15.4").foregroundStyle(.secondary))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Display name") {
                        TextField("", text: $displayName,
                                  prompt: Text(placeholderName).foregroundStyle(.secondary))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                }

                destinationButton(.baseVM, icon: "shippingbox.fill", title: "Base VM",
                    subtitle: "Use as a source for cloning new VMs. Appears in the Base VMs view.")

                destinationButton(.virtualMachine, icon: "desktopcomputer", title: "Virtual Machine",
                    subtitle: "Use directly as a running VM. Appears in the Virtual Machines view.")

                destinationButton(.justPull, icon: "arrow.down.circle", title: "Just Pull the Image",
                    subtitle: "Download it into tart's cache without registering a VM — the image is already usable as a Base VM once pulled.")
            }
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380)
        .onAppear { osVersion = initialOSVersion }
    }

    private func destinationButton(_ destination: RegistryPullDestination, icon: String,
                                   title: String, subtitle: String) -> some View {
        Button {
            onChoose(destination,
                     osVersion.trimmingCharacters(in: .whitespaces),
                     displayName.trimmingCharacters(in: .whitespaces))
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2).frame(width: 36).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
