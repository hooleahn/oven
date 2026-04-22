import SwiftUI

// MARK: - CirrusLabsTemplateSheet
// Presents the CirrusLabs vanilla Packer templates. Selecting one copies
// the HCL content from GitHub into the user's custom templates folder.
// The created template is read-write — it is not flagged as isBase.

struct CirrusLabsTemplateSheet: View {
    @EnvironmentObject var templateStore: PackerTemplateStore
    let onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Per-template fetch state
    @State private var importing: String? = nil      // template id currently fetching
    @State private var errorMessage: String? = nil

    private let templates = CirrusLabsTemplateStore.vanillaTemplates

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            templateList
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 400)
        .alert("Import Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cirrus Labs Vanilla Templates").font(.headline)
                Text("Official open-source Packer templates from cirruslabs/macos-image-templates")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16).background(.bar)
    }

    // MARK: - Template list

    private var templateList: some View {
        List {
            Section {
                ForEach(templates) { tmpl in
                    CirrusLabsTemplateRow(
                        template: tmpl,
                        isAlreadyImported: isImported(tmpl),
                        isImporting: importing == tmpl.id,
                        onImport: { importTemplate(tmpl) }
                    )
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Vanilla Templates")
                    Spacer()
                    Link(destination: URL(string: "https://github.com/cirruslabs/macos-image-templates")!) {
                        Label("View on GitHub", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            } footer: {
                Text("These templates are read-only originals from CirrusLabs. Importing creates a custom copy in your templates folder that you can freely edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Helpers

    private func isImported(_ tmpl: CirrusLabsVanillaTemplate) -> Bool {
        templateStore.customFullTemplates.contains { $0.filename == tmpl.defaultFilename }
    }

    private func importTemplate(_ tmpl: CirrusLabsVanillaTemplate) {
        guard importing == nil else { return }
        importing = tmpl.id
        errorMessage = nil
        Task {
            do {
                let id = try await templateStore.createFromCirrus(tmpl)
                importing = nil
                dismiss()
                onCreated(id)
            } catch {
                importing = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - CirrusLabsTemplateRow

private struct CirrusLabsTemplateRow: View {
    let template: CirrusLabsVanillaTemplate
    let isAlreadyImported: Bool
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // OS icon
            Image(systemName: "apple.logo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(template.displayName)
                    .bold()
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(template.osName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("·").font(.caption2).foregroundStyle(.quaternary)
                    Link(destination: template.githubURL) {
                        Text("View source")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Action
            if isImporting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Importing…").font(.caption).foregroundStyle(.secondary)
                }
            } else if isAlreadyImported {
                Text("Imported")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            } else {
                Button("Create Custom Copy", action: onImport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
