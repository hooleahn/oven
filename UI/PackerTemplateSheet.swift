import SwiftUI

/// Shows the packer template (and vars file, when captured) that was actually
/// used for a base VM's most recent build attempt. Content is a snapshot taken
/// at build time — see `VirtualMachine.lastBuildTemplateContent` — since the
/// live template file on disk can be overwritten or deleted before a failed
/// build is ever inspected.
struct PackerTemplateSheet: View {
    let baseVM: VirtualMachine
    @Environment(\.dismiss) private var dismiss
    @State private var showingVars = false

    private var hasVars: Bool {
        !(baseVM.lastBuildVarsContent ?? "").isEmpty
    }

    private var currentContent: String {
        let content = showingVars ? baseVM.lastBuildVarsContent : baseVM.lastBuildTemplateContent
        return content ?? "No template was captured for this build."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Packer Template")
                        .font(.headline)
                    Text(baseVM.packerTemplateName.isEmpty ? baseVM.name : baseVM.packerTemplateName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasVars {
                    Picker("", selection: $showingVars) {
                        Text("Template").tag(false)
                        Text("Vars").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(currentContent, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy to clipboard")
                .accessibilityLabel("Copy template")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            ScrollView {
                Text(currentContent)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 560)
    }
}
