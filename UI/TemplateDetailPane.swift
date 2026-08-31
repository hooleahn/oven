import SwiftUI

// MARK: - TemplateDetailPane
// Shown when a Full Template (.pkr.hcl) is selected.

struct TemplateDetailPane: View {
    let template: PackerTemplate
    @Bindable var model: RecipesViewModel

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
    private var isAnyDirty: Bool { model.isDirty || model.isMetadataDirty }

    private var versionList: [String] {
        sofaVersions.isEmpty
            ? (MacOSRelease.Name(rawValue: model.editedOSName)?.fallbackVersions ?? [])
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
                text: $model.editedContent,
                isEditable: canEdit,
                onChange: { if !model.isLoadingContent { model.isDirty = true } }
            )
            if let result = model.validationResult {
                validationBanner(result)
            }
        }
        .task { await loadVersions(for: model.editedOSName) }
        .onChange(of: model.editedOSName) { _, newName in
            Task { await loadVersions(for: newName) }
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.editedDisplayName.isEmpty ? template.filename : model.editedDisplayName).bold()
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
            if let err = model.saveError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .lineLimit(1)
            }
            if model.isSaving { ProgressView().controlSize(.small) }

            if template.isBase {
                Button("Create Custom Copy", action: onFork)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                if model.isValidating {
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
                NSPasteboard.general.setString(model.editedContent, forType: .string)
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
                    TextField("", text: $model.editedDisplayName,
                              prompt: Text(template.filename).foregroundStyle(.tertiary))
                        .onChange(of: model.editedDisplayName) { _, _ in if !model.isLoadingContent { model.isMetadataDirty = true } }
                } else {
                    Text(template.displayName.isEmpty ? template.filename : template.displayName)
                }
            }
            GridRow {
                Text("Description").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                if canEdit {
                    TextField("", text: $model.editedDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: model.editedDescription) { _, _ in if !model.isLoadingContent { model.isMetadataDirty = true } }
                } else {
                    Text(template.templateDescription.isEmpty ? "—" : template.templateDescription)
                        .foregroundStyle(template.templateDescription.isEmpty ? .tertiary : .primary)
                }
            }
            GridRow {
                Text("Target OS").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                if canEdit {
                    HStack(spacing: 8) {
                        Picker("", selection: $model.editedOSName) {
                            Text("Any").tag("")
                            ForEach(MacOSRelease.Name.allCases, id: \.self) {
                                Text($0.rawValue).tag($0.rawValue)
                            }
                        }
                        .labelsHidden().frame(width: 120)
                        .onChange(of: model.editedOSName) { _, _ in if !model.isLoadingContent { model.isMetadataDirty = true } }

                        if !model.editedOSName.isEmpty {
                            Picker("", selection: $model.editedOSVersion) {
                                Text("Any version").tag("")
                                ForEach(versionList, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 120)
                            .onChange(of: model.editedOSVersion) { _, _ in if !model.isLoadingContent { model.isMetadataDirty = true } }
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
            Button { model.validationResult = nil } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isSuccess ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
    }
}
