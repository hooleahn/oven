import SwiftUI

// MARK: - VarsFileDetailPane
// Shown when a Template Variables (.pkrvars.hcl) file is selected.

struct VarsFileDetailPane: View {
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
    @Binding var isLoadingContent: Bool

    let onSave: () -> Void
    let onRevert: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var copied = false
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false

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
            toolbar
            Divider()
            securityBanner
            Divider()
            metadataHeader
            Divider()
            HCLEditor(
                text: $editedContent,
                isEditable: true,
                onChange: { if !isLoadingContent { isDirty = true } }
            )
        }
        .task { await loadVersions(for: editedOSName) }
        .onChange(of: editedOSName) { _, newName in
            Task { await loadVersions(for: newName) }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(editedDisplayName.isEmpty ? template.filename : editedDisplayName).bold()
                    if isAnyDirty {
                        Text("Edited")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .background(.bar, in: Rectangle())
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
                    .font(.caption).foregroundStyle(.red).lineLimit(1)
            }
            if isSaving { ProgressView() }
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

    // MARK: - Security banner

    private var securityBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Avoid storing sensitive values in vars files")
                    .fontWeight(.medium)
                Text("Passwords and secrets written here are stored in plain text. Use Keychain-backed credentials in the Build sheet instead — Oven injects them securely at build time.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Metadata header

    private var metadataHeader: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Display Name").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                TextField("", text: $editedDisplayName,
                          prompt: Text(template.filename).foregroundStyle(.tertiary))
                    .onChange(of: editedDisplayName) { _, _ in if !isLoadingContent { isMetadataDirty = true } }
            }
            GridRow {
                Text("Description").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                TextField("", text: $editedDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: editedDescription) { _, _ in if !isLoadingContent { isMetadataDirty = true } }
            }
            GridRow {
                Text("Target OS").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
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
            }
            GridRow {
                Text("File Path").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(template.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.background)
    }
}
