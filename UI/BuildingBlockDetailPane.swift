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
    @State private var editedOSName: String = ""
    @State private var editedOSVersion: String = ""
    @State private var editedProvisioner: BuildingBlock.ProvisionerType = .shell
    @State private var editedContent: String = ""
    @State private var isDirty = false
    @State private var isContentDirty = false
    @State private var isLoading = false
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false

    private var canEdit: Bool { !block.isBase }
    private var isAnyDirty: Bool { isDirty || isContentDirty }

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
        .task { await loadVersions(for: editedOSName) }
        .onChange(of: editedOSName) { _, newName in
            if canEdit { Task { await loadVersions(for: newName) } }
        }
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
                            .background(.quaternary, in: Capsule())
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
                            .onChange(of: editedOSName) { _, _ in if !isLoading { isDirty = true } }

                            if !editedOSName.isEmpty {
                                Picker("", selection: $editedOSVersion) {
                                    Text("Any version").tag("")
                                    ForEach(versionList, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().frame(width: 120)
                                .onChange(of: editedOSVersion) { _, _ in if !isLoading { isDirty = true } }
                                if isFetchingVersions {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                        }
                    }
                }
                .font(.callout)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    if !block.blockDescription.isEmpty {
                        GridRow {
                            Text("Description").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            Text(block.blockDescription).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("Target OS").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        let os = block.osName.isEmpty ? "Any" : block.osName
                        let ver = block.osVersion.isEmpty ? "" : " \(block.osVersion)"
                        Text("\(os)\(ver)").foregroundStyle(block.osName.isEmpty ? .tertiary : .primary)
                    }
                }
                .font(.callout)
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
        isLoading          = true
        editedDisplayName  = block.displayName
        editedDescription  = block.blockDescription
        editedOSName       = block.osName
        editedOSVersion    = block.osVersion
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
            createdAt: block.createdAt,
            osName: editedOSName,
            osVersion: editedOSVersion
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

// MARK: - BootCommandEditSheet

/// Modal sheet for creating or editing a BootCommandBlock.
/// Each command line is one HCL string entry in the boot_command array.
struct BootCommandEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cmd: BootCommandBlock?
    let onSave: (BootCommandBlock) -> Void

    @State private var displayName: String
    @State private var description: String
    @State private var osName: MacOSRelease.Name
    @State private var osVersion: String
    @State private var commandText: String   // newline-separated for editing
    @State private var diagnostics: [BootCommandLinter.Diagnostic] = []

    init(cmd: BootCommandBlock? = nil, onSave: @escaping (BootCommandBlock) -> Void) {
        self.cmd = cmd
        self.onSave = onSave
        _displayName = State(initialValue: cmd?.displayName ?? "")
        _description = State(initialValue: cmd?.blockDescription ?? "")
        let name = cmd.flatMap { MacOSRelease.Name(rawValue: $0.osName) } ?? .sequoia
        _osName = State(initialValue: name)
        _osVersion = State(initialValue: cmd?.osVersion ?? "")
        _commandText = State(initialValue: cmd?.commandLines.joined(separator: "\n") ?? Self.placeholder)
    }

    private static let placeholder = #""""<wait60s><spacebar>""""#

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(cmd == nil ? "New Boot Command Block" : "Edit Boot Command Block").bold()
                Spacer()
                if !diagnostics.isEmpty {
                    Label("\(diagnostics.count) issue\(diagnostics.count == 1 ? "" : "s")",
                          systemImage: diagnostics.contains(where: { $0.severity == .error })
                            ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(diagnostics.contains(where: { $0.severity == .error })
                            ? .red : .orange)
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { saveCmd() }
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
                                  prompt: Text("e.g. macOS 15 Setup Assistant").foregroundStyle(.tertiary))
                    }
                    LabeledContent("Description") {
                        TextField("", text: $description, axis: .vertical).lineLimit(2...5)
                    }
                }
                Section("OS Compatibility") {
                    Picker("OS", selection: $osName) {
                        ForEach(MacOSRelease.Name.allCases, id: \.self) {
                            Text($0.displayLabel).tag($0)
                        }
                    }
                    LabeledContent("Version") {
                        TextField("", text: $osVersion,
                                  prompt: Text("Leave empty to match any version").foregroundStyle(.tertiary))
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 240)

            Divider()

            // Syntax-highlighted command lines editor
            BootCommandEditor(text: $commandText, isEditable: true, onChange: { runLinter() })
                .onChange(of: commandText, initial: true) { _, _ in runLinter() }

            // Diagnostics panel
            if !diagnostics.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(diagnostics) { d in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: d.severity == .error
                                      ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(d.severity == .error ? .red : .orange)
                                    .font(.caption)
                                Text("Line \(d.line): \(d.message)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 120)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(minWidth: 600, idealWidth: 660, minHeight: 560)
    }

    private func runLinter() {
        let lines = commandText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        diagnostics = BootCommandLinter.lint(lines: lines)
    }

    private func saveCmd() {
        let lines = commandText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let b = BootCommandBlock(
            id: cmd?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            blockDescription: description,
            commandLines: lines,
            isBase: false,
            createdAt: cmd?.createdAt ?? Date(),
            osName: osName.rawValue,
            osVersion: osVersion.trimmingCharacters(in: .whitespaces)
        )
        onSave(b)
        dismiss()
    }
}

// MARK: - BootCommandDetailPane

struct BootCommandDetailPane: View {
    let cmd: BootCommandBlock
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSave: (BootCommandBlock) -> Void

    @State private var showingEditSheet = false
    @State private var copied = false
    @State private var diagnostics: [BootCommandLinter.Diagnostic] = []

    // Inline editing state (custom blocks only)
    @State private var editedDisplayName: String = ""
    @State private var editedDescription: String = ""
    @State private var editedOSName: String = ""
    @State private var editedOSVersion: String = ""
    @State private var isDirty = false
    @State private var isLoading = false
    @State private var sofaVersions: [String] = []
    @State private var isFetchingVersions = false

    private var canEdit: Bool { !cmd.isBase }

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

    // Read-only text binding for the editor
    private var commandText: String { cmd.commandLines.joined(separator: "\n") }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            cmdHeader
            Divider()
            // Syntax-highlighted read-only display
            BootCommandEditor(text: .constant(commandText), isEditable: false, onChange: {})
            // Diagnostics panel (read-only view of linter results)
            if !diagnostics.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(diagnostics) { d in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: d.severity == .error
                                      ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(d.severity == .error ? .red : .orange)
                                    .font(.caption)
                                Text("Line \(d.line): \(d.message)")
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 100)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onAppear {
            syncFromCmd()
            diagnostics = BootCommandLinter.lint(lines: cmd.commandLines)
        }
        .onChange(of: cmd.id) { _, _ in
            syncFromCmd()
            diagnostics = BootCommandLinter.lint(lines: cmd.commandLines)
        }
        .task { await loadVersions(for: editedOSName) }
        .onChange(of: editedOSName) { _, newName in
            if canEdit { Task { await loadVersions(for: newName) } }
        }
        .sheet(isPresented: $showingEditSheet) {
            BootCommandEditSheet(cmd: cmd) { updated in onSave(updated) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if canEdit {
                        Text(editedDisplayName.isEmpty ? "Untitled Block" : editedDisplayName).bold()
                    } else {
                        Text(cmd.displayName).bold()
                    }
                    if cmd.isBase {
                        Text("Base Block")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    } else if isDirty {
                        Text("Edited")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if !diagnostics.isEmpty {
                        let hasError = diagnostics.contains(where: { $0.severity == .error })
                        Label("\(diagnostics.count)", systemImage: hasError
                              ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((hasError ? Color.red : Color.orange).opacity(0.1), in: Capsule())
                            .foregroundStyle(hasError ? .red : .orange)
                            .help("\(diagnostics.count) linting issue\(diagnostics.count == 1 ? "" : "s") found")
                    }
                }
                if !cmd.isBase {
                    Text("Created " + cmd.createdAt.formatted(date: .numeric, time: .omitted))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()

            Button {
                let text = cmd.commandLines.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .foregroundStyle(copied ? .green : .primary)

            if cmd.isBase {
                Button("Create Custom Copy", action: onDuplicate)
                    .buttonStyle(.bordered)
            } else {
                Button("Revert") { syncFromCmd() }.disabled(!isDirty)
                Button("Save") { commitSave() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
                Divider().frame(height: 16)
                Button("Edit Commands") { showingEditSheet = true }
                    .buttonStyle(.bordered)
                Divider().frame(height: 16)
                Button(action: onDuplicate) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Duplicate")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.red).help("Delete")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    private var cmdHeader: some View {
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
                            .onChange(of: editedOSName) { _, _ in if !isLoading { isDirty = true } }

                            if !editedOSName.isEmpty {
                                Picker("", selection: $editedOSVersion) {
                                    Text("Any version").tag("")
                                    ForEach(versionList, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().frame(width: 120)
                                .onChange(of: editedOSVersion) { _, _ in if !isLoading { isDirty = true } }
                                if isFetchingVersions {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                        }
                    }
                    GridRow {
                        Text("Commands").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text("\(cmd.commandLines.count) line\(cmd.commandLines.count == 1 ? "" : "s")")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    if !cmd.blockDescription.isEmpty {
                        GridRow {
                            Text("Description").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            Text(cmd.blockDescription).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("Target OS").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        let os = cmd.osName.isEmpty ? "Any" : cmd.osName
                        let ver = cmd.osVersion.isEmpty ? "" : " \(cmd.osVersion)"
                        Text("\(os)\(ver)").foregroundStyle(cmd.osName.isEmpty ? .tertiary : .primary)
                    }
                    GridRow {
                        Text("Commands").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text("\(cmd.commandLines.count) line\(cmd.commandLines.count == 1 ? "" : "s")")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.background)
    }

    // MARK: - Helpers

    private func syncFromCmd() {
        isLoading           = true
        editedDisplayName   = cmd.displayName
        editedDescription   = cmd.blockDescription
        editedOSName        = cmd.osName
        editedOSVersion     = cmd.osVersion
        isDirty             = false
        Task { @MainActor in self.isLoading = false }
    }

    private func commitSave() {
        let updated = BootCommandBlock(
            id: cmd.id,
            displayName: editedDisplayName.trimmingCharacters(in: .whitespaces),
            blockDescription: editedDescription,
            commandLines: cmd.commandLines,
            isBase: false,
            createdAt: cmd.createdAt,
            osName: editedOSName,
            osVersion: editedOSVersion
        )
        onSave(updated)
        isDirty = false
    }
}
