import SwiftUI

// MARK: - RecipesView
// Three-tab view: Full Templates | Template Variables | Building Blocks
// Uses HSplitView for a proper resizable sidebar/detail divider.

struct RecipesView: View {
    @Environment(AppTheme.self) private var theme
    @Environment(PackerTemplateStore.self) private var templateStore
    @Environment(BuildingBlockStore.self) private var blockStore
    @Environment(BaseVMStore.self) private var baseVMStore
    @Environment(AppState.self) private var appState

    @Environment(RecipesViewModel.self) private var model

    // Bindable wrapper so computed sub-view properties can produce bindings.
    private var bindableModel: Bindable<RecipesViewModel> { Bindable(model) }

    @State private var isRefreshing: Bool = false
    @State private var refreshRotation: Double = 0

    // PackerService for validation — resolved from shared deps
    private var packerService: PackerService? {
        SharedStores.packerService
    }

    var body: some View {
        baseContent
            .toolbar(content: recipesToolbar)
            .modifier(RecipesDialogs(
                model: model,
                bindableModel: bindableModel,
                templateStore: templateStore,
                blockStore: blockStore,
                theme: theme
            ))
    }

    private var baseContent: some View {
        HSplitView {
            sidebar
            detail
        }
        .navigationTitle(theme.recipes)
        .task { updateWindowTitle() }
        .onChange(of: model.selectedTemplateID, initial: false, { _, _ in updateWindowTitle() })
        .onChange(of: model.selectedBlockID,    initial: false, { _, _ in updateWindowTitle() })
        .onChange(of: model.selectedTab,        initial: false, { _, _ in updateWindowTitle() })
        .searchable(text: bindableModel.searchText, prompt: "Search…")
        .onChange(of: model.selectedTab) { _, _ in
            if let id = model.selectedTemplateID { model.saveDraft(for: id) }
            model.selectedTemplateID = nil
            model.selectedBlockID = nil
            model.selectedBootCommandID = nil
            model.editedContent = ""
        }
    }

    // MARK: - Sidebar

    // MARK: - Toolbar

    @ToolbarContentBuilder private func recipesToolbar() -> some ToolbarContent {
        // 1. Navigation group — tab picker
        ToolbarItemGroup(placement: .navigation) {
            Picker("", selection: bindableModel.selectedTab) {
                ForEach(RecipesTab.allCases, id: \.self) { tab in
                    Image(systemName: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)
        }

        // 2. Primary action — New recipe object (⌘N)
        ToolbarItem(placement: .primaryAction) {
            Button { model.isPresentingNewSheet = true } label: {
                Label("New…", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New template or building block (⌘N)")
        }

        // 3. Secondary actions
        ToolbarItemGroup(placement: .secondaryAction) {
            recipesSecondaryActions
        }

        // 4. Flexible space
        ToolbarItem(placement: .automatic) {
            Spacer()
        }

        // 5. Search provided by .searchable — no explicit item needed

        // 6. No sort menu for recipes

        // 7. Refresh (⌘R)
        ToolbarItem(placement: .automatic) {
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    refreshRotation = 360
                }
                templateStore.load()
                isRefreshing = false
                refreshRotation = 0
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? refreshRotation : 0))
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh templates (⌘R)")
        }
    }

    // MARK: - Toolbar secondary actions (extracted to help the type checker)

    @ViewBuilder private var recipesSecondaryActions: some View {
        // Import from Cirrus Labs — only for templates tab
        if model.selectedTab == .templates {
            Button { model.isPresentingCirrusSheet = true } label: {
                Label("Import from Cirrus Labs", systemImage: "arrow.down.circle")
            }
            .help("Import a template from Cirrus Labs")
        }

        recipesTemplateDuplicateButton
        recipesTemplateDeleteButton
    }

    @ViewBuilder private var recipesTemplateDuplicateButton: some View {
        if model.selectedTab == .templates || model.selectedTab == .varsFiles,
           let id = model.selectedTemplateID,
           let tmpl = templateStore.template(id: id),
           !tmpl.isBase {
            Button { _ = templateStore.duplicate(id: id) } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("d", modifiers: .command)
            .help("Duplicate selected template (⌘D)")
        } else if model.selectedTab == .blocks {
            if let id = model.selectedBlockID,
               let block = blockStore.blocks.first(where: { $0.id == id }),
               !block.isBase {
                Button {
                    let copy = blockStore.duplicate(block)
                    model.selectedBlockID = copy.id
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("d", modifiers: .command)
                .help("Duplicate selected block (⌘D)")
            } else if let id = model.selectedBootCommandID,
                      let cmd = blockStore.bootCommands.first(where: { $0.id == id }),
                      !cmd.isBase {
                Button {
                    let copy = blockStore.duplicateBootCommand(cmd)
                    model.selectedBootCommandID = copy.id
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("d", modifiers: .command)
                .help("Duplicate selected boot command (⌘D)")
            }
        }
    }

    @ViewBuilder private var recipesTemplateDeleteButton: some View {
        if model.selectedTab == .templates || model.selectedTab == .varsFiles,
           let id = model.selectedTemplateID,
           let tmpl = templateStore.template(id: id),
           !tmpl.isBase {
            Button(role: .destructive) { model.confirmDeleteTemplateID = id } label: {
                Label("Delete", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .help("Delete selected template (⌘⌫)")
        } else if model.selectedTab == .blocks {
            if let id = model.selectedBlockID,
               let block = blockStore.blocks.first(where: { $0.id == id }),
               !block.isBase {
                Button(role: .destructive) { model.confirmDeleteBlockID = id } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Delete selected block (⌘⌫)")
            } else if let id = model.selectedBootCommandID,
                      let cmd = blockStore.bootCommands.first(where: { $0.id == id }),
                      !cmd.isBase {
                Button(role: .destructive) { model.confirmDeleteBootCommandID = id } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Delete selected boot command (⌘⌫)")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            switch model.selectedTab {
            case .templates:  templatesList
            case .varsFiles:  varsFilesList
            case .blocks:     blocksList
            }
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 340)
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
                                        Button("Duplicate") { _ = templateStore.duplicate(id: tmpl.id) }
                                        Divider()
                                        Button("Copy to Clipboard") {
                                            if let content = try? String(contentsOf: tmpl.url, encoding: .utf8) {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(content, forType: .string)
                                            }
                                        }
                                        Button("Show in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([tmpl.url])
                                        }
                                        Button("Open in Editor") {
                                            NSWorkspace.shared.open(tmpl.url)
                                        }
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
                                    Button("Duplicate") { _ = templateStore.duplicate(id: tmpl.id) }
                                    Divider()
                                    Button("Copy to Clipboard") {
                                        if let content = try? String(contentsOf: tmpl.url, encoding: .utf8) {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(content, forType: .string)
                                        }
                                    }
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([tmpl.url])
                                    }
                                    Button("Open in Editor") {
                                        NSWorkspace.shared.open(tmpl.url)
                                    }
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
                List(selection: bindableModel.selectedBlockItem) {
                    // Provisioner building blocks
                    if !customBlocks.isEmpty {
                        Section("Custom Building Blocks") {
                            ForEach(customBlocks) { block in
                                BuildingBlockRow(block: block)
                                    .tag(BlockSelection.block(block.id))
                                    .contextMenu {
                                        Button("Duplicate") {
                                            let copy = blockStore.duplicate(block)
                                            model.selectedBlockItem = .block(copy.id)
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
                                    .tag(BlockSelection.block(block.id))
                            }
                        }
                    }
                    // Boot command blocks
                    if !customCmds.isEmpty {
                        Section("Custom Boot Commands") {
                            ForEach(customCmds) { cmd in
                                BootCommandRow(cmd: cmd)
                                    .tag(BlockSelection.bootCommand(cmd.id))
                                    .contextMenu {
                                        Button("Duplicate") {
                                            let copy = blockStore.duplicateBootCommand(cmd)
                                            model.selectedBlockItem = .bootCommand(copy.id)
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
                                    .tag(BlockSelection.bootCommand(cmd.id))
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
                .environment(theme)
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
                    editedOSName: bindableModel.editedOSName,
                    editedOSVersion: bindableModel.editedOSVersion,
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
            ContentUnavailableView(
                "No Recipe Selected",
                systemImage: "doc.text",
                description: Text("Select an item from the list.")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyDetail(_ title: String, image: String, description: String) -> some View {
        EmptyStateView(title, systemImage: image, description: description)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Window title

    private func updateWindowTitle() {
        let tabName = model.selectedTab.rawValue
        switch model.selectedTab {
        case .templates:
            if let id = model.selectedTemplateID,
               let tmpl = templateStore.template(id: id) {
                let name = tmpl.displayName.isEmpty ? tmpl.filename : tmpl.displayName
                appState.windowTitle = name
                appState.windowSubtitle = tabName
            } else {
                appState.windowTitle = theme.recipes
                appState.windowSubtitle = ""
            }
        case .varsFiles:
            if let id = model.selectedTemplateID,
               let tmpl = templateStore.template(id: id) {
                let name = tmpl.displayName.isEmpty ? tmpl.filename : tmpl.displayName
                appState.windowTitle = name
                appState.windowSubtitle = tabName
            } else {
                appState.windowTitle = theme.recipes
                appState.windowSubtitle = ""
            }
        case .blocks:
            if let id = model.selectedBlockID,
               let block = blockStore.blocks.first(where: { $0.id == id }) {
                appState.windowTitle = block.displayName
                appState.windowSubtitle = tabName
            } else {
                appState.windowTitle = theme.recipes
                appState.windowSubtitle = ""
            }
        }
    }
}

// MARK: - RecipesDialogs (ViewModifier to reduce type-checker pressure on RecipesView.body)

private struct RecipesDialogs: ViewModifier {
    let model: RecipesViewModel
    let bindableModel: Bindable<RecipesViewModel>
    let templateStore: PackerTemplateStore
    let blockStore: BuildingBlockStore
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
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
            .sheet(isPresented: bindableModel.isPresentingNewSheet) {
                NewPackerObjectSheet(
                    onCreatedTemplate: { id in
                        model.selectedTemplateID = id
                        model.loadTemplateContent(id, from: templateStore)
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
                .environment(theme)
                .environment(templateStore)
            }
            .sheet(isPresented: bindableModel.isPresentingCirrusSheet) {
                CirrusLabsTemplateSheet { id in
                    model.selectedTemplateID = id
                    model.loadTemplateContent(id, from: templateStore)
                    model.selectedTab = .templates
                }
                .environment(templateStore)
            }
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(block.displayName).bold().lineLimit(1)
                Label(block.provisioner.label, systemImage: block.provisioner.systemImage)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - BootCommandRow

struct BootCommandRow: View {
    let cmd: BootCommandBlock
    var body: some View {
        HStack(spacing: 8) {
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
        }
        .padding(.vertical, 2)
    }
}
