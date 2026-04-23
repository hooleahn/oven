import SwiftUI

// MARK: - RecipesView
// Three-tab view: Full Templates | Template Variables | Building Blocks
// Uses HSplitView for a proper resizable sidebar/detail divider.

struct RecipesView: View {
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var templateStore: PackerTemplateStore
    @EnvironmentObject var blockStore: BuildingBlockStore
    @EnvironmentObject var baseVMStore: BaseVMStore

    @Environment(RecipesViewModel.self) private var model

    // Bindable wrapper so computed sub-view properties can produce bindings.
    private var bindableModel: Bindable<RecipesViewModel> { Bindable(model) }

    // PackerService for validation — resolved from shared deps
    private var packerService: PackerService? {
        SharedStores.packerService
    }

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .navigationTitle(theme.recipes)
        .searchable(text: bindableModel.searchText, prompt: "Search…")
        .onChange(of: model.selectedTab) { _, _ in
            // Persist any unsaved edits to the draft cache before clearing selection,
            // so they can be restored if the user returns to the same item.
            if let id = model.selectedTemplateID { model.saveDraft(for: id) }
            model.selectedTemplateID = nil
            model.selectedBlockID = nil
            model.selectedBootCommandID = nil
            model.editedContent = ""
        }
        // Fork base confirmation
        .confirmationDialog(
            "Create a Custom Copy?",
            isPresented: bindableModel.showForkConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create Custom Copy") {
                if let newID = model.confirmFork(in: templateStore) {
                    model.selectedTemplateID = newID
                    model.loadTemplateContent(newID, from: templateStore)
                }
            }
            Button("Cancel", role: .cancel) { model.showForkConfirmation = false }
        } message: {
            Text("Base Templates are read-only. A custom copy will be created in your templates folder so you can edit it freely.")
        }
        // Delete template confirmation
        .confirmationDialog(
            templateStore.template(id: model.confirmDeleteTemplateID ?? UUID())
                .map { "Delete \"\($0.displayName)\"?" } ?? "Delete template?",
            isPresented: Binding(
                get: { model.confirmDeleteTemplateID != nil },
                set: { if !$0 { model.confirmDeleteTemplateID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = model.confirmDeleteTemplateID {
                Button("Delete", role: .destructive) {
                    if model.selectedTemplateID == id { model.selectedTemplateID = nil }
                    try? templateStore.delete(id: id)
                    model.confirmDeleteTemplateID = nil
                }
                Button("Cancel", role: .cancel) { model.confirmDeleteTemplateID = nil }
            }
        } message: { Text("The file will be moved to the Trash.") }
        // Delete block confirmation
        .confirmationDialog(
            blockStore.blocks.first(where: { $0.id == model.confirmDeleteBlockID })
                .map { "Delete \"\($0.displayName)\"?" } ?? "Delete block?",
            isPresented: Binding(
                get: { model.confirmDeleteBlockID != nil },
                set: { if !$0 { model.confirmDeleteBlockID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = model.confirmDeleteBlockID {
                Button("Delete", role: .destructive) {
                    if model.selectedBlockID == id { model.selectedBlockID = nil }
                    blockStore.delete(id: id)
                    model.confirmDeleteBlockID = nil
                }
                Button("Cancel", role: .cancel) { model.confirmDeleteBlockID = nil }
            }
        } message: { Text("This building block will be permanently removed.") }
        // Delete boot command confirmation
        .confirmationDialog(
            blockStore.bootCommands.first(where: { $0.id == model.confirmDeleteBootCommandID })
                .map { "Delete \"\($0.displayName)\"?" } ?? "Delete boot command?",
            isPresented: Binding(
                get: { model.confirmDeleteBootCommandID != nil },
                set: { if !$0 { model.confirmDeleteBootCommandID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = model.confirmDeleteBootCommandID {
                Button("Delete", role: .destructive) {
                    if model.selectedBootCommandID == id { model.selectedBootCommandID = nil }
                    blockStore.deleteBootCommand(id: id)
                    model.confirmDeleteBootCommandID = nil
                }
                Button("Cancel", role: .cancel) { model.confirmDeleteBootCommandID = nil }
            }
        } message: { Text("This boot command block will be permanently removed.") }
        // Rename template
        .alert("Rename Template", isPresented: Binding(
            get: { model.renamingTemplateID != nil },
            set: { if !$0 { model.renamingTemplateID = nil } }
        )) {
            TextField("Filename", text: bindableModel.renameText)
            Button("Rename") {
                if let id = model.renamingTemplateID {
                    let newID = templateStore.rename(id: id, to: model.renameText)
                    model.renamingTemplateID = nil
                    if let newID {
                        model.selectedTemplateID = newID
                        model.loadTemplateContent(newID, from: templateStore)
                    }
                }
            }
            Button("Cancel", role: .cancel) { model.renamingTemplateID = nil }
        }
        // New object sheet
        .sheet(isPresented: bindableModel.isPresentingNewSheet) {
            NewPackerObjectSheet(
                onCreatedTemplate: { id in
                    model.selectedTemplateID = id
                    model.loadTemplateContent(id, from: templateStore)
                    // Switch to the right tab
                    if let tmpl = templateStore.template(id: id) {
                        model.selectedTab = tmpl.kind == .varsFile ? .varsFiles : .templates
                    }
                },
                onCreatedBlock: { block in
                    blockStore.add(block)
                    model.selectedBlockID = block.id
                    model.selectedTab = .blocks
                },
                onCreatedBootCommand: { cmd in
                    blockStore.addBootCommand(cmd)
                    model.selectedBootCommandID = cmd.id
                    model.selectedBlockID = nil
                    model.selectedTab = .blocks
                }
            )
            .environmentObject(theme)
            .environment(templateStore)
        }
        // Cirrus Labs vanilla templates sheet
        .sheet(isPresented: bindableModel.isPresentingCirrusSheet) {
            CirrusLabsTemplateSheet { id in
                model.selectedTemplateID = id
                model.loadTemplateContent(id, from: templateStore)
                model.selectedTab = .templates
            }
            .environmentObject(templateStore)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            switch model.selectedTab {
            case .templates:  templatesList
            case .varsFiles:  varsFilesList
            case .blocks:     blocksList
            }
        }
        .frame(minWidth: 210, idealWidth: 250, maxWidth: 340)
    }

    // MARK: - Sidebar toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: bindableModel.selectedTab) {
                ForEach(RecipesTab.allCases, id: \.self) { tab in
                    Image(systemName: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)

            Spacer()

            if model.selectedTab == .templates {
                Button { model.isPresentingCirrusSheet = true } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Import from Cirrus Labs")
            }

            Button { templateStore.load() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Refresh templates")

            Button { model.isPresentingNewSheet = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("New…")
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    // MARK: - Templates list (computed property on RecipesView so templateStore is read
    // directly as an @EnvironmentObject of this view, same pattern as blocksList)

    private var templatesList: some View {
        let q = model.searchText.lowercased()
        let allCustom = templateStore.customFullTemplates
        let allBase   = templateStore.baseFullTemplates
        let customs = q.isEmpty ? allCustom : allCustom.filter {
            $0.displayName.lowercased().contains(q) || $0.filename.lowercased().contains(q) || $0.osName.lowercased().contains(q)
        }
        let bases = q.isEmpty ? allBase : allBase.filter {
            $0.displayName.lowercased().contains(q) || $0.filename.lowercased().contains(q)
        }
        return Group {
            if templateStore.fullTemplates.isEmpty {
                emptyState(theme.recipes, image: "doc.text",
                           description: "Create a .pkr.hcl template to drive Base VM builds.")
            } else if customs.isEmpty && bases.isEmpty {
                ContentUnavailableView.search
            } else {
                List(selection: bindableModel.selectedTemplateID) {
                    if !customs.isEmpty {
                        Section("Custom") {
                            ForEach(customs) { tmpl in
                                PackerTemplateRow(template: tmpl)
                                    .tag(tmpl.id)
                                    .contextMenu {
                                        Button("Rename") {
                                            model.renamingTemplateID = tmpl.id
                                            model.renameText = tmpl.url.deletingPathExtension().lastPathComponent
                                        }
                                        Button("Duplicate") { _ = templateStore.duplicate(id: tmpl.id) }
                                        Divider()
                                        Button("Delete", role: .destructive) { model.confirmDeleteTemplateID = tmpl.id }
                                    }
                            }
                        }
                    }
                    if !bases.isEmpty {
                        Section("Base Templates") {
                            ForEach(bases) { tmpl in
                                PackerTemplateRow(template: tmpl)
                                    .tag(tmpl.id)
                                    .contextMenu {
                                        Button("Create Custom Copy") { _ = templateStore.forkBase(id: tmpl.id) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: model.selectedTemplateID) { _, id in
                    if let id { model.loadTemplateContent(id, from: templateStore) }
                }
            }
        }
    }

    // MARK: - Vars files list

    private var varsFilesList: some View {
        let q = model.searchText.lowercased()
        let all = templateStore.varsFiles
        let filtered = q.isEmpty ? all : all.filter {
            $0.displayName.lowercased().contains(q) || $0.filename.lowercased().contains(q)
        }
        return Group {
            if templateStore.varsFiles.isEmpty {
                emptyState("Template Variables", image: "slider.horizontal.3",
                           description: "Create a .pkrvars.hcl file to override template settings.")
            } else if filtered.isEmpty {
                ContentUnavailableView.search
            } else {
                List(selection: bindableModel.selectedTemplateID) {
                    Section("Variables Files") {
                        ForEach(filtered) { tmpl in
                            PackerTemplateRow(template: tmpl)
                                .tag(tmpl.id)
                                .contextMenu {
                                    Button("Rename") {
                                        model.renamingTemplateID = tmpl.id
                                        model.renameText = tmpl.url.deletingPathExtension().lastPathComponent
                                    }
                                    Button("Duplicate") { _ = templateStore.duplicate(id: tmpl.id) }
                                    Divider()
                                    Button("Delete", role: .destructive) { model.confirmDeleteTemplateID = tmpl.id }
                                }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: model.selectedTemplateID) { _, id in
                    if let id { model.loadTemplateContent(id, from: templateStore) }
                }
            }
        }
    }

    // MARK: - Blocks list

    private var blocksList: some View {
        let filteredBlocks = model.filteredBlocks(from: blockStore)
        let baseBlocks     = filteredBlocks.filter {  $0.isBase }
        let customBlocks   = filteredBlocks.filter { !$0.isBase }
        let filteredCmds   = model.filteredBootCommands(from: blockStore)
        let baseCmds       = filteredCmds.filter {  $0.isBase }
        let customCmds     = filteredCmds.filter { !$0.isBase }
        let hasAny = !blockStore.blocks.isEmpty || !blockStore.bootCommands.isEmpty
        let hasFiltered = !filteredBlocks.isEmpty || !filteredCmds.isEmpty
        return Group {
            if !hasAny {
                emptyState("No Building Blocks", image: "puzzlepiece", description: "")
            } else if !hasFiltered {
                ContentUnavailableView.search
            } else {
                // Two parallel selections: one for provisioner blocks, one for boot command blocks.
                // We drive them manually via onTapGesture so we can clear the other on selection.
                List {
                    // Provisioner building blocks
                    if !customBlocks.isEmpty {
                        Section("Custom Building Blocks") {
                            ForEach(customBlocks) { block in
                                BuildingBlockRow(block: block)
                                    .listRowBackground(model.selectedBlockID == block.id
                                        ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.selectedBlockID = block.id
                                        model.selectedBootCommandID = nil
                                    }
                                    .contextMenu {
                                        Button("Duplicate") {
                                            let copy = blockStore.duplicate(block)
                                            model.selectedBlockID = copy.id
                                            model.selectedBootCommandID = nil
                                        }
                                        Button("Delete", role: .destructive) {
                                            model.confirmDeleteBlockID = block.id
                                        }
                                    }
                            }
                        }
                    }
                    if !baseBlocks.isEmpty {
                        Section("Base Building Blocks") {
                            ForEach(baseBlocks) { block in
                                BuildingBlockRow(block: block)
                                    .listRowBackground(model.selectedBlockID == block.id
                                        ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.selectedBlockID = block.id
                                        model.selectedBootCommandID = nil
                                    }
                            }
                        }
                    }
                    // Boot command blocks
                    if !customCmds.isEmpty {
                        Section("Custom Boot Commands") {
                            ForEach(customCmds) { cmd in
                                BootCommandRow(cmd: cmd)
                                    .listRowBackground(model.selectedBootCommandID == cmd.id
                                        ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.selectedBootCommandID = cmd.id
                                        model.selectedBlockID = nil
                                    }
                                    .contextMenu {
                                        Button("Duplicate") {
                                            let copy = blockStore.duplicateBootCommand(cmd)
                                            model.selectedBootCommandID = copy.id
                                            model.selectedBlockID = nil
                                        }
                                        Button("Delete", role: .destructive) {
                                            model.confirmDeleteBootCommandID = cmd.id
                                        }
                                    }
                            }
                        }
                    }
                    if !baseCmds.isEmpty {
                        Section("Base Boot Commands") {
                            ForEach(baseCmds) { cmd in
                                BootCommandRow(cmd: cmd)
                                    .listRowBackground(model.selectedBootCommandID == cmd.id
                                        ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        model.selectedBootCommandID = cmd.id
                                        model.selectedBlockID = nil
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detail: some View {
        if model.selectedTab == .blocks {
            if let id = model.selectedBlockID,
               let block = blockStore.blocks.first(where: { $0.id == id }) {
                BuildingBlockDetailPane(
                    block: block,
                    onDuplicate: {
                        let copy = blockStore.duplicate(block)
                        model.selectedBlockID = copy.id
                    },
                    onDelete: { model.confirmDeleteBlockID = id },
                    onSave: { updated in blockStore.update(id: updated.id) { $0 = updated } }
                )
            } else if let id = model.selectedBootCommandID,
                      let cmd = blockStore.bootCommands.first(where: { $0.id == id }) {
                BootCommandDetailPane(
                    cmd: cmd,
                    onDuplicate: {
                        let copy = blockStore.duplicateBootCommand(cmd)
                        model.selectedBootCommandID = copy.id
                    },
                    onDelete: { model.confirmDeleteBootCommandID = id },
                    onSave: { updated in blockStore.updateBootCommand(id: updated.id) { $0 = updated } }
                )
            } else {
                emptyDetail("No Block Selected", image: "puzzlepiece",
                            description: "Select a building block or boot command to view details.")
            }
        } else if let id = model.selectedTemplateID,
                  let tmpl = templateStore.template(id: id) {
            if tmpl.kind == .fullTemplate {
                TemplateDetailPane(
                    template: tmpl,
                    editedContent: bindableModel.editedContent,
                    editedDisplayName: bindableModel.editedDisplayName,
                    editedDescription: bindableModel.editedDescription,
                    editedOSName: bindableModel.editedOSName,
                    editedOSVersion: bindableModel.editedOSVersion,
                    isDirty: bindableModel.isDirty,
                    isMetadataDirty: bindableModel.isMetadataDirty,
                    isSaving: bindableModel.isSaving,
                    saveError: bindableModel.saveError,
                    isValidating: bindableModel.isValidating,
                    validationResult: bindableModel.validationResult,
                    isLoadingContent: bindableModel.isLoadingContent,
                    onSave: { model.save(in: templateStore) },
                    onRevert: { model.revert(from: templateStore) },
                    onValidate: {
                        if let svc = packerService {
                            model.validate(template: tmpl, packerService: svc, store: templateStore)
                        }
                    },
                    onFork: { model.requestFork(id: id) },
                    onDuplicate: { _ = templateStore.duplicate(id: id) },
                    onDelete: { model.confirmDeleteTemplateID = id }
                )
                .environmentObject(theme)
                .onChange(of: model.isDirty) { _, dirty in
                    if dirty, let id = model.selectedTemplateID {
                        templateStore.update(id: id) { $0.validationState = .unknown }
                        model.validationResult = nil
                    }
                }
            } else {
                VarsFileDetailPane(
                    template: tmpl,
                    editedContent: bindableModel.editedContent,
                    editedDisplayName: bindableModel.editedDisplayName,
                    editedDescription: bindableModel.editedDescription,
                    isDirty: bindableModel.isDirty,
                    isMetadataDirty: bindableModel.isMetadataDirty,
                    isSaving: bindableModel.isSaving,
                    saveError: bindableModel.saveError,
                    isLoadingContent: bindableModel.isLoadingContent,
                    onSave: { model.save(in: templateStore) },
                    onRevert: { model.revert(from: templateStore) },
                    onDuplicate: { _ = templateStore.duplicate(id: id) },
                    onDelete: { model.confirmDeleteTemplateID = id }
                )
            }
        } else {
            let image = model.selectedTab == .varsFiles ? "slider.horizontal.3" : "doc.text"
            let label = model.selectedTab == .varsFiles ? "No File Selected" : "No Template Selected"
            emptyDetail(label, image: image, description: "Select an item from the list.")
        }
    }

    // MARK: - Helpers

    private func emptyState(_ title: String, image: String, description: String) -> some View {
        EmptyStateView(title, systemImage: image, description: description) {
            Button("New…") { model.isPresentingNewSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyDetail(_ title: String, image: String, description: String) -> some View {
        EmptyStateView(title, systemImage: image, description: description)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PackerTemplateRow

struct PackerTemplateRow: View {
    let template: PackerTemplate
    var body: some View {
        HStack(spacing: 8) {
            validationIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(template.displayName.isEmpty ? template.filename : template.displayName)
                    .bold()
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !template.osName.isEmpty {
                        Text(template.osName + (template.osVersion.isEmpty ? "" : " \(template.osVersion)"))
                            .foregroundStyle(.secondary)
                    }
                    Text(template.filename)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var validationIcon: some View {
        switch template.validationState {
        case .valid:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .invalid:
            Image(systemName: "xmark.seal.fill")
                .foregroundStyle(.red)
                .font(.callout)
        case .validating:
            ProgressView().controlSize(.mini)
                .frame(width: 14, height: 14)
        case .unknown:
            Color.clear.frame(width: 14, height: 14)
        }
    }
}

// MARK: - BuildingBlockRow

struct BuildingBlockRow: View {
    let block: BuildingBlock
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(block.displayName).bold().lineLimit(1)
            Label(block.provisioner.label, systemImage: block.provisioner.systemImage)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - BootCommandRow

struct BootCommandRow: View {
    let cmd: BootCommandBlock
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cmd.displayName).bold().lineLimit(1)
            HStack(spacing: 6) {
                Label("\(cmd.commandLines.count) lines", systemImage: "command")
                    .font(.caption).foregroundStyle(.secondary)
                if !cmd.osName.isEmpty {
                    Text(cmd.osName + (cmd.osVersion.isEmpty ? "" : " \(cmd.osVersion)"))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
