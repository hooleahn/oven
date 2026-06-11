import SwiftUI

// MARK: - TemplateDetailPane
// Shown when a Full Template (.pkr.hcl) is selected.

struct TemplateDetailPane: View {
    let template: PackerTemplate
    @Binding var editedContent: String
    @Binding var editedDisplayName: String
    @Binding var editedDescription: String
    @Binding var editedOSName: String
    @Binding var editedOSVersion: String
    @Binding var isDirty: Bool
    @Binding var isMetadataDirty: Bool
    @Binding var isSaving: Bool
    @Binding var saveError: String?
    @Binding var isValidating: Bool
    @Binding var validationResult: String?

    @Binding var isLoadingContent: Bool

    let onSave: () -> Void
    let onRevert: () -> Void
    let onValidate: () -> Void
    let onFork: () -> Void       // called when user tries to edit a base template
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @Environment(AppTheme.self) private var theme
    @State private var copied = false
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false

    private var canEdit: Bool { !template.isBase }
    private var isAnyDirty: Bool { isDirty || isMetadataDirty }

    private var versionList: [String] {
        sofaVersions.isEmpty
            ? (MacOSRelease.Name(rawValue: editedOSName)?.fallbackVersions ?? [])
            : sofaVersions
    }

    private func loadVersions(for osNameRaw: String) async {
        guard let release = MacOSRelease.Name(rawValue: osNameRaw), !osNameRaw.isEmpty else {
            sofaVersions = []
            return
        }
        isFetchingVersions = true
        sofaVersions = await SOFAService.shared.versions(for: release)
        isFetchingVersions = false
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            metadataHeader
            Divider()
            HCLEditor(
                text: $editedContent,
                isEditable: canEdit,
                onChange: { if !isLoadingContent { isDirty = true } }
            )
            if let result = validationResult {
                validationBanner(result)
            }
        }
        .task { await loadVersions(for: editedOSName) }
        .onChange(of: editedOSName) { _, newName in
            Task { await loadVersions(for: newName) }
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(editedDisplayName.isEmpty ? template.filename : editedDisplayName).bold()
                    if template.isBase {
                        Text("Base Template")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .background(.bar, in: Rectangle())
                            .foregroundStyle(.secondary)
                    } else if isAnyDirty {
                        Text("Edited")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 6) {
                    Text(template.filename)
                        .font(.caption).foregroundStyle(.tertiary)
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text("Modified " + template.modifiedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .lineLimit(1)
            }
            if isSaving { ProgressView().controlSize(.small) }

            if template.isBase {
                Button("Create Custom Copy", action: onFork)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                if isValidating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Validating…").font(.caption)
                    }
                } else {
                    Button("Validate", action: onValidate)
                        .buttonStyle(.bordered)
                }
                Button("Revert", action: onRevert).disabled(!isAnyDirty)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isAnyDirty)
                Divider().frame(height: 16)
                Button(action: onDuplicate) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless).help("Duplicate")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).foregroundStyle(.red).help("Delete")
            }
            Divider().frame(height: 16)
            fileActionsMenu
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    // MARK: - File actions overflow menu

    private var fileActionsMenu: some View {
        Menu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(editedContent, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy to Clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            Divider()
            Button {
                NSWorkspace.shared.open(template.url)
            } label: {
                Label("Open in Editor", systemImage: "pencil")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([template.url])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More actions")
    }

    // MARK: - Metadata header

    private var metadataHeader: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Display Name").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                if canEdit {
                    TextField("", text: $editedDisplayName,
                              prompt: Text(template.filename).foregroundStyle(.tertiary))
                        .onChange(of: editedDisplayName) { _, _ in if !isLoadingContent { isMetadataDirty = true } }
                } else {
                    Text(template.displayName.isEmpty ? template.filename : template.displayName)
                }
            }
            GridRow {
                Text("Description").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                if canEdit {
                    TextField("", text: $editedDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: editedDescription) { _, _ in if !isLoadingContent { isMetadataDirty = true } }
                } else {
                    Text(template.templateDescription.isEmpty ? "—" : template.templateDescription)
                        .foregroundStyle(template.templateDescription.isEmpty ? .tertiary : .primary)
                }
            }
            GridRow {
                Text("Target OS").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                if canEdit {
                    HStack(spacing: 8) {
                        Picker("", selection: $editedOSName) {
                            Text("Any").tag("")
                            ForEach(MacOSRelease.Name.allCases, id: \.self) {
                                Text($0.rawValue).tag($0.rawValue)
                            }
                        }
                        .labelsHidden().frame(width: 120)
                        .onChange(of: editedOSName) { _, _ in if !isLoadingContent { isMetadataDirty = true } }

                        if !editedOSName.isEmpty {
                            Picker("", selection: $editedOSVersion) {
                                Text("Any version").tag("")
                                ForEach(versionList, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 120)
                            .onChange(of: editedOSVersion) { _, _ in if !isLoadingContent { isMetadataDirty = true } }
                            if isFetchingVersions {
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                } else {
                    let os = template.osName.isEmpty ? "Any" : template.osName
                    let ver = template.osVersion.isEmpty ? "" : " \(template.osVersion)"
                    Text("\(os)\(ver)").foregroundStyle(template.osName.isEmpty ? .tertiary : .primary)
                }
            }
            GridRow {
                Text("File Path").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(template.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
    }

    // MARK: - Validation banner

    private func validationBanner(_ result: String) -> some View {
        let isSuccess = result.contains("✓ Template is valid")
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isSuccess ? .green : .red)
            Text(result)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isSuccess ? .green : .red)
                .textSelection(.enabled)
            Spacer()
            Button { validationResult = nil } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSuccess ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
    }
}
