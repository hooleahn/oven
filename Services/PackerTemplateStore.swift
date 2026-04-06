import SwiftUI

// MARK: - PackerTemplateStore

@MainActor
@Observable
final class PackerTemplateStore: ObservableObject {

    private(set) var templates: [PackerTemplate] = []

    private var templatesRoot: URL { AppSettings.load().packerTemplatesRoot }

    init() { load() }

    // MARK: - Computed views

    var fullTemplates: [PackerTemplate] { templates.filter { $0.kind == .fullTemplate } }
    var varsFiles: [PackerTemplate]     { templates.filter { $0.kind == .varsFile } }

    var baseFullTemplates: [PackerTemplate]   { fullTemplates.filter {  $0.isBase } }
    var customFullTemplates: [PackerTemplate] { fullTemplates.filter { !$0.isBase } }

    func fullTemplates(for osName: String, version: String) -> [PackerTemplate] {
        customFullTemplates.filter {
            (osName.isEmpty || $0.osName == osName) &&
            (version.isEmpty || $0.osVersion == version || $0.osVersion.isEmpty)
        }
    }

    func template(id: UUID) -> PackerTemplate? {
        templates.first { $0.id == id }
    }

    // MARK: - Load

    func load() {
        guard FileManager.default.fileExists(atPath: templatesRoot.path) else {
            templates = []; return
        }
        var all: [PackerTemplate] = []
        all += read(from: templatesRoot, isBase: false)
        let defaultsDir = templatesRoot.appendingPathComponent("defaults")
        if FileManager.default.fileExists(atPath: defaultsDir.path) {
            all += read(from: defaultsDir, isBase: true)
        }
        templates = all
    }

    private func read(from dir: URL, isBase: Bool) -> [PackerTemplate] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            ($0.lastPathComponent.hasSuffix(".pkr.hcl") ||
             $0.lastPathComponent.hasSuffix(".pkrvars.hcl")) &&
            !$0.lastPathComponent.hasPrefix(".")
        } ?? []

        return urls.compactMap { url -> PackerTemplate? in
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
            let meta: PackerTemplateMetadata
            if let existing = PackerTemplateMetadata.load(for: url) {
                meta = existing
            } else {
                let stem = url.deletingPathExtension().lastPathComponent
                let inferred = stem.replacingOccurrences(of: "-", with: " ").capitalized
                meta = PackerTemplateMetadata(displayName: inferred, osName: "", osVersion: "")
                try? meta.save(for: url)
            }
            let existingID = templates.first(where: { $0.url == url })?.id ?? meta.id
            // Restore validated state if the file has not been modified since last validation
            let restoredValidationState: PackerTemplate.ValidationState = {
                guard let validatedAt = meta.validatedAt else { return .unknown }
                return mod <= validatedAt ? .valid : .unknown
            }()
            return PackerTemplate(
                id: existingID,
                filename: url.lastPathComponent,
                url: url,
                content: "",
                modifiedAt: mod,
                isBase: isBase,
                kind: PackerTemplate.kind(for: url),
                displayName: meta.displayName,
                templateDescription: meta.templateDescription,
                osName: meta.osName,
                osVersion: meta.osVersion,
                validationState: restoredValidationState
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Content

    func loadContent(for id: UUID) -> String? {
        guard let tmpl = template(id: id),
              let content = try? String(contentsOf: tmpl.url, encoding: .utf8) else { return nil }
        return content
    }

    // MARK: - Update (mirrors BuildingBlockStore.update exactly)
    // Caller builds the updated PackerTemplate and we do a full element replacement,
    // exactly like BlockStore does `blocks[i] = updated`. This guarantees objectWillChange fires.

    func update(id: UUID, _ apply: (inout PackerTemplate) -> Void) {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return }
        var copy = templates[i]   // copy out
        apply(&copy)              // mutate the copy
        templates[i] = copy      // assign back — triggers templates[i].set → objectWillChange
    }

    // MARK: - Save content to disk

    func saveContent(_ content: String, for id: UUID) throws {
        guard let tmpl = template(id: id) else { return }
        try content.write(to: tmpl.url, atomically: true, encoding: .utf8)
    }

    /// Stamps the sidecar with the current date so the validated state survives relaunch.
    func markValidated(id: UUID) {
        guard let tmpl = template(id: id) else { return }
        var meta = PackerTemplateMetadata.load(for: tmpl.url) ??
            PackerTemplateMetadata(id: id, displayName: tmpl.displayName)
        meta.validatedAt = Date()
        try? meta.save(for: tmpl.url)
    }

    /// Clears the validated stamp so the template is no longer considered valid after relaunch.
    func clearValidated(id: UUID) {
        guard let tmpl = template(id: id) else { return }
        var meta = PackerTemplateMetadata.load(for: tmpl.url) ??
            PackerTemplateMetadata(id: id, displayName: tmpl.displayName)
        meta.validatedAt = nil
        try? meta.save(for: tmpl.url)
    }

    // MARK: - Save metadata to disk

    func saveMetadata(id: UUID, displayName: String, description: String,
                      osName: String, osVersion: String) throws {
        guard let tmpl = template(id: id) else { return }
        var meta = PackerTemplateMetadata.load(for: tmpl.url) ??
            PackerTemplateMetadata(id: id, displayName: displayName)
        meta.displayName = displayName
        meta.templateDescription = description
        meta.osName = osName
        meta.osVersion = osVersion
        try meta.save(for: tmpl.url)
    }

    // MARK: - Structural mutations (need full reload)

    func delete(id: UUID) throws {
        guard let tmpl = template(id: id), !tmpl.isBase else { return }
        try FileManager.default.trashItem(at: tmpl.url, resultingItemURL: nil)
        let sidecar = PackerTemplateMetadata.sidecarURL(for: tmpl.url)
        try? FileManager.default.trashItem(at: sidecar, resultingItemURL: nil)
        load()
    }

    func duplicate(id: UUID) -> UUID? {
        guard let tmpl = template(id: id) else { return nil }
        let base = tmpl.url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-copy", with: "")
        var newURL: URL; var counter = 2
        repeat {
            let suffix = counter == 2 ? "-copy" : "-copy-\(counter)"
            newURL = tmpl.url.deletingLastPathComponent()
                .appendingPathComponent("\(base)\(suffix).\(tmpl.kind.fileExtension)")
            counter += 1
        } while FileManager.default.fileExists(atPath: newURL.path)
        guard (try? FileManager.default.copyItem(at: tmpl.url, to: newURL)) != nil else { return nil }
        var newMeta = PackerTemplateMetadata.load(for: tmpl.url) ??
            PackerTemplateMetadata(displayName: tmpl.displayName)
        newMeta = PackerTemplateMetadata(
            displayName: "\(tmpl.displayName) (Copy)",
            templateDescription: newMeta.templateDescription,
            osName: newMeta.osName, osVersion: newMeta.osVersion)
        try? newMeta.save(for: newURL)
        load()
        return templates.first(where: { $0.url == newURL })?.id
    }

    func rename(id: UUID, to newStem: String) -> UUID? {
        guard let tmpl = template(id: id), !tmpl.isBase else { return nil }
        let newFilename = newStem.hasSuffix(".\(tmpl.kind.fileExtension)")
            ? newStem : "\(newStem).\(tmpl.kind.fileExtension)"
        let newURL = tmpl.url.deletingLastPathComponent().appendingPathComponent(newFilename)
        guard newURL != tmpl.url,
              (try? FileManager.default.moveItem(at: tmpl.url, to: newURL)) != nil else { return nil }
        let oldSidecar = PackerTemplateMetadata.sidecarURL(for: tmpl.url)
        let newSidecar = PackerTemplateMetadata.sidecarURL(for: newURL)
        try? FileManager.default.moveItem(at: oldSidecar, to: newSidecar)
        load()
        return templates.first(where: { $0.url == newURL })?.id
    }

    @discardableResult
    func create(kind: PackerTemplateKind, displayName: String, description: String,
                osName: String, osVersion: String, filename: String,
                starterContent: String) throws -> UUID {
        try FileManager.default.createDirectory(at: templatesRoot, withIntermediateDirectories: true)
        let url = templatesRoot.appendingPathComponent(filename)
        let meta = try PackerTemplateMetadata.create(
            for: url, displayName: displayName, description: description,
            osName: osName, osVersion: osVersion)
        let header = meta.hclCommentHeader(filename: filename)
        try (header + starterContent).write(to: url, atomically: true, encoding: .utf8)
        load()
        return meta.id
    }

    func forkBase(id: UUID) -> UUID? { duplicate(id: id) }
}
