import SwiftUI


struct PullDestinationSheet: View {
    let image: RegistryImage
    let onChoose: (Bool, String, String) -> Void  // asBase, username, password
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultPackerUsername") private var defaultPackerUsername: String = "baker"
    @State private var username: String = ""
    @State private var password: String = ""

    private var imageName: String {
        image.imageRef.components(separatedBy: "/").last ?? image.imageRef
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
                    LabeledContent("Username") {
                        TextField("", text: $username,
                                  prompt: Text("e.g. baker").foregroundStyle(.secondary))
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Password") {
                        SecureField("", text: $password,
                                    prompt: Text("optional, stored in Keychain").foregroundStyle(.secondary))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    onChoose(true, username, password)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2).frame(width: 36).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Base VM").fontWeight(.medium)
                            Text("Use as a source for cloning new VMs. Appears in the Base VMs view.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Button {
                    onChoose(false, username, password)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "desktopcomputer")
                            .font(.title2).frame(width: 36).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Virtual Machine").fontWeight(.medium)
                            Text("Use directly as a running VM. Appears in the Virtual Machines view.")
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
            .padding(20)
        }
        .frame(minWidth: 400, idealWidth: 440, minHeight: 280)
    }
}
