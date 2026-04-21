import SwiftUI

// MARK: - BuildingBlockDetailPane

struct BuildingBlockDetailPane: View {
    let block: BuildingBlock
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSave: (BuildingBlock) -> Void

    @State private var copied = false

    // Inline editing state (custom blocks only)
    @State private var editedDisplayName: String = ""
    @State private var editedDescription: String = ""
    @State private var editedProvisioner: BuildingBlock.ProvisionerType = .shell
    @State private var editedContent: String = ""
    @State private var isDirty = false
    @State private var isContentDirty = false
    @State private var isLoading = false

    private var canEdit: Bool { !block.isBase }
    private var isAnyDirty: Bool { isDirty || isContentDirty }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            blockHeader
            Divider()
            HCLEditor(
                text: canEdit ? Binding(get: { editedContent }, set: { editedContent = $0; if !isLoading { isContentDirty = true } })
                              : .constant(block.hclContent),
                isEditable: canEdit,
                onChange: { if !isLoading { isContentDirty = true } }
            )
        }
        .onAppear { syncFromBlock() }
        .onChange(of: block.id) { _, _ in syncFromBlock() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if canEdit {
                        Text(editedDisplayName.isEmpty ? "Untitled Block" : editedDisplayName).bold()
                    } else {
                        Text(block.displayName).bold()
                    }
                    // Provisioner badge
                    if canEdit {
                        Menu {
                            ForEach(BuildingBlock.ProvisionerType.allCases, id: \.self) { type in
                                Button {
                                    editedProvisioner = type; isDirty = true
                                } label: {
                                    Label(type.label, systemImage: type.systemImage)
                                }
                            }
                        } label: {
                            Label(editedProvisioner.label, systemImage: editedProvisioner.systemImage)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    } else {
                        Label(block.provisioner.label, systemImage: block.provisioner.systemImage)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if block.isBase {
                        Text("Base Block")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    } else if isAnyDirty {
                        Text("Edited")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                if !block.isBase {
                    Text("Created " + block.createdAt.formatted(date: .numeric, time: .omitted))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(canEdit ? editedContent : block.hclContent, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .foregroundStyle(copied ? .green : .primary)

            if block.isBase {
                Button("Create Custom Copy", action: onDuplicate)
                    .buttonStyle(.bordered)
            } else {
                Button("Revert") { syncFromBlock() }.disabled(!isAnyDirty)
                Button("Save") { commitSave() }
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
            Menu {
                Button {
                    let content = canEdit ? editedContent : block.hclContent
                    NSWorkspace.shared.open(writeTempHCL(content: content, name: block.displayName))
                } label: {
                    Label("Open in Editor", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    // MARK: - Helpers

    private func writeTempHCL(content: String, name: String) -> URL {
        let safe = name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).hcl")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Block header (description + metadata)

    private var blockHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canEdit {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Display Name").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        TextField("", text: $editedDisplayName,
                                  prompt: Text("Block name").foregroundStyle(.tertiary))
                            .onChange(of: editedDisplayName) { _, _ in if !isLoading { isDirty = true } }
                    }
                    GridRow {
                        Text("Description").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        TextField("", text: $editedDescription, axis: .vertical)
                            .lineLimit(2...4)
                            .onChange(of: editedDescription) { _, _ in if !isLoading { isDirty = true } }
                    }
                }
                .font(.callout)
            } else {
                if !block.blockDescription.isEmpty {
                    Text(block.blockDescription).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.background)
    }

    // MARK: - Helpers

    private func syncFromBlock() {
        // Set isLoading before assignments and clear it on the next run loop tick,
        // so SwiftUI's deferred onChange callbacks are still gated after this returns.
        isLoading      = true
        editedDisplayName  = block.displayName
        editedDescription  = block.blockDescription
        editedProvisioner  = block.provisioner
        editedContent      = block.hclContent
        isDirty            = false
        isContentDirty     = false
        Task { @MainActor in self.isLoading = false }
    }

    private func commitSave() {
        let updated = BuildingBlock(
            id: block.id,
            displayName: editedDisplayName.trimmingCharacters(in: .whitespaces),
            blockDescription: editedDescription,
            provisioner: editedProvisioner,
            hclContent: editedContent,
            isBase: false,
            createdAt: block.createdAt
        )
        onSave(updated)
        isDirty = false
        isContentDirty = false
    }
}

// MARK: - BuildingBlockEditSheet (kept for creation flow)

struct BuildingBlockEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let block: BuildingBlock?
    let onSave: (BuildingBlock) -> Void

    @State private var displayName: String
    @State private var description: String
    @State private var provisioner: BuildingBlock.ProvisionerType
    @State private var hclContent: String

    init(block: BuildingBlock? = nil, onSave: @escaping (BuildingBlock) -> Void) {
        self.block = block
        self.onSave = onSave
        _displayName = State(initialValue: block?.displayName ?? "")
        _description = State(initialValue: block?.blockDescription ?? "")
        _provisioner = State(initialValue: block?.provisioner ?? .shell)
        _hclContent  = State(initialValue: block?.hclContent ?? """
  provisioner "shell" {
    inline = [
      "echo 'Hello from Packer'"
    ]
  }
""")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(block == nil ? "New Building Block" : "Edit Building Block").bold()
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { saveBlock() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("Details") {
                    LabeledContent("Name") {
                        TextField("", text: $displayName,
                                  prompt: Text("e.g. Install Rosetta").foregroundStyle(.tertiary))
                    }
                    LabeledContent("Description") {
                        TextField("", text: $description, axis: .vertical).lineLimit(2...5)
                    }
                    Picker("Provisioner type", selection: $provisioner) {
                        ForEach(BuildingBlock.ProvisionerType.allCases, id: \.self) {
                            Label($0.label, systemImage: $0.systemImage).tag($0)
                        }
                    }
                }
            }
            .formStyle(.grouped).frame(height: 220)
            Divider()
            HCLEditor(text: $hclContent, isEditable: true, onChange: {})
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480)
    }

    private func saveBlock() {
        let b = BuildingBlock(
            id: block?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            blockDescription: description,
            provisioner: provisioner,
            hclContent: hclContent,
            isBase: false,
            createdAt: block?.createdAt ?? Date()
        )
        onSave(b)
        dismiss()
    }
}
