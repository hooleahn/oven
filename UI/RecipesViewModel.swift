import SwiftUI

// MARK: - RecipesTab

enum RecipesTab: String, CaseIterable {
    case templates    = "Templates"
    case varsFiles    = "Vars Files"
    case blocks       = "Building Blocks"

    var systemImage: String {
        switch self {
        case .templates: return "doc.text"
        case .varsFiles: return "slider.horizontal.3"
        case .blocks:    return "puzzlepiece"
        }
    }
}

// MARK: - RecipesViewModel

@MainActor
@Observable
final class RecipesViewModel {

    // Navigation
    var selectedTab: RecipesTab = .templates
    var selectedTemplateID: UUID? = nil
    var selectedBlockID: UUID? = nil

    // Editor state
    var editedContent: String = ""
    var isDirty: Bool = false
    var isSaving: Bool = false
    var saveError: String? = nil

    // Metadata editing (for full templates)
    var editedDisplayName: String = ""
    var editedDescription: String = ""
    var editedOSName: String = ""
    var editedOSVersion: String = ""
    var isMetadataDirty: Bool = false

    // In-memory draft cache: preserves unsaved edits across tab switches
    private struct TemplateDraft {
        var content: String
        var displayName: String
        var description: String
        var osName: String
        var osVersion: String
        var isDirty: Bool
        var isMetadataDirty: Bool
    }
    private var templateDrafts: [UUID: TemplateDraft] = [:]

    // Validation state
    var isValidating: Bool = false
    var validationResult: String? = nil

    // Sheet / dialog state
    var isPresentingNewSheet: Bool = false
    var confirmDeleteTemplateID: UUID? = nil
    var confirmDeleteBlockID: UUID? = nil
    var renamingTemplateID: UUID? = nil
    var renameText: String = ""
    var showForkConfirmation: Bool = false
    var pendingForkID: UUID? = nil

    // Search
    var searchText: String = ""

    // Guard flag to suppress onChange dirty-marking during programmatic content load
    var isLoadingContent: Bool = false

    // MARK: - Filtered lists

    func filteredFullTemplates(from store: PackerTemplateStore) -> [PackerTemplate] {
        let all = store.fullTemplates
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.filename.lowercased().contains(q) ||
            $0.osName.lowercased().contains(q) ||
            $0.osVersion.lowercased().contains(q)
        }
    }

    func filteredVarsFiles(from store: PackerTemplateStore) -> [PackerTemplate] {
        let all = store.varsFiles
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.filename.lowercased().contains(q) ||
            $0.templateDescription.lowercased().contains(q)
        }
    }

    func filteredBlocks(from store: BuildingBlockStore) -> [BuildingBlock] {
        let all = store.blocks
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.blockDescription.lowercased().contains(q) ||
            $0.provisioner.label.lowercased().contains(q)
        }
    }

    // MARK: - Template selection

    func selectTemplate(_ id: UUID, in store: PackerTemplateStore) {
        guard id != selectedTemplateID else { return }
        selectedTemplateID = id
        loadTemplateContent(id, from: store)
    }

    func loadTemplateContent(_ id: UUID, from store: PackerTemplateStore) {
        guard let tmpl = store.template(id: id) else { return }
        saveError = nil
        validationResult = nil
        isValidating = false
        // Suppress onChange dirty-marking while we populate the editor fields.
        // isLoadingContent is cleared on the next run loop tick so SwiftUI's deferred
        // onChange callbacks (which fire after the current synchronous mutation) are
        // still gated before they can mark the content as dirty.
        isLoadingContent = true
        Task { @MainActor in self.isLoadingContent = false }
        // Restore from draft cache if there are unsaved edits
        if let draft = templateDrafts[id] {
            editedContent = draft.content
            editedDisplayName = draft.displayName
            editedDescription = draft.description
            editedOSName = draft.osName
            editedOSVersion = draft.osVersion
            isDirty = draft.isDirty
            isMetadataDirty = draft.isMetadataDirty
        } else {
            editedContent = store.loadContent(for: id) ?? ""
            editedDisplayName = tmpl.displayName
            editedDescription = tmpl.templateDescription
            editedOSName = tmpl.osName
            editedOSVersion = tmpl.osVersion
            isDirty = false
            isMetadataDirty = false
        }
    }

    /// True if there are any unsaved edits in the current editor or the draft cache.
    var hasUnsavedChanges: Bool {
        isDirty || isMetadataDirty || !templateDrafts.isEmpty
    }

    /// Persists the current editor state into the draft cache for the given template.
    func saveDraft(for id: UUID) {
        guard isDirty || isMetadataDirty else {
            templateDrafts.removeValue(forKey: id)
            return
        }
        templateDrafts[id] = TemplateDraft(
            content: editedContent,
            displayName: editedDisplayName,
            description: editedDescription,
            osName: editedOSName,
            osVersion: editedOSVersion,
            isDirty: isDirty,
            isMetadataDirty: isMetadataDirty
        )
    }

    // MARK: - Save / revert

    func save(in store: PackerTemplateStore) {
        guard let id = selectedTemplateID else { return }
        isSaving = true
        saveError = nil
        // Capture values before clearing dirty flags
        let newDisplayName   = editedDisplayName
        let newDescription   = editedDescription
        let newOSName        = editedOSName
        let newOSVersion     = editedOSVersion
        let newContent       = editedContent
        let wasContentDirty  = isDirty
        let wasMetadataDirty = isMetadataDirty
        do {
            if wasContentDirty  { try store.saveContent(newContent, for: id) }
            if wasMetadataDirty {
                try store.saveMetadata(id: id, displayName: newDisplayName,
                    description: newDescription, osName: newOSName, osVersion: newOSVersion)
            }
            // Clear model state and draft cache
            isDirty = false
            isMetadataDirty = false
            isSaving = false
            templateDrafts.removeValue(forKey: id)
            // Defer store.update() to the next run loop iteration so its objectWillChange
            // fires in a separate render pass from the @Observable model changes above.
            // This guarantees SwiftUI re-evaluates templatesList with the fresh array.
            Task { @MainActor in
                store.update(id: id) { t in
                    if wasMetadataDirty {
                        t.displayName         = newDisplayName
                        t.templateDescription = newDescription
                        t.osName              = newOSName
                        t.osVersion           = newOSVersion
                    }
                    if wasContentDirty {
                        t.content = newContent
                        // Content changed — previous validation result is no longer valid
                        t.validationState = .unknown
                    }
                }
                if wasContentDirty {
                    store.clearValidationResult(id: id)
                }
            }
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    func revert(from store: PackerTemplateStore) {
        guard let id = selectedTemplateID else { return }
        templateDrafts.removeValue(forKey: id)
        loadTemplateContent(id, from: store)
    }

    // MARK: - Fork base template

    func requestFork(id: UUID) {
        pendingForkID = id
        showForkConfirmation = true
    }

    func confirmFork(in store: PackerTemplateStore) -> UUID? {
        guard let id = pendingForkID else { return nil }
        let newID = store.forkBase(id: id)
        pendingForkID = nil
        showForkConfirmation = false
        return newID
    }

    // MARK: - Validation

    func validate(template tmpl: PackerTemplate, packerService: PackerService,
                  store: PackerTemplateStore) {
        isValidating = true
        validationResult = nil
        store.update(id: tmpl.id) { $0.validationState = .validating }
        Task {
            var lines: [String] = []
            for await line in await packerService.validateStandalone(at: tmpl.url) {
                lines.append(line)
                validationResult = lines.joined(separator: "\n")
            }
            isValidating = false
            let result = lines.joined(separator: "\n")
            let succeeded = result.contains("✓ Template is valid")
            store.update(id: tmpl.id) { t in
                t.validationState = succeeded ? .valid : .invalid(result)
            }
            // Persist to sidecar so the badge survives relaunch
            store.saveValidationResult(id: tmpl.id, succeeded: succeeded, output: result)
        }
    }
}
