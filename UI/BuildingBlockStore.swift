import SwiftUI

// MARK: - BuildingBlockStore

@MainActor
@Observable
final class BuildingBlockStore {

    // MARK: - Provisioner blocks

    private(set) var blocks: [BuildingBlock] = []

    var baseBlocks: [BuildingBlock]   { blocks.filter {  $0.isBase } }
    var customBlocks: [BuildingBlock] { blocks.filter { !$0.isBase } }

    // MARK: - Boot command blocks

    private(set) var bootCommands: [BootCommandBlock] = []

    var baseBootCommands: [BootCommandBlock]   { bootCommands.filter {  $0.isBase } }
    var customBootCommands: [BootCommandBlock] { bootCommands.filter { !$0.isBase } }

    // MARK: - Init

    init() { load() }

    // MARK: - Filtering helpers

    /// Returns provisioner blocks compatible with the given OS name + version.
    /// A block with empty osName is always included (universal).
    /// A block with matching osName and empty osVersion matches any version of that OS.
    func blocks(for osName: String, version: String) -> [BuildingBlock] {
        blocks.filter { block in
            block.osName.isEmpty ||
            (block.osName == osName && (block.osVersion.isEmpty || block.osVersion == version))
        }
    }

    /// Returns boot command blocks compatible with the given OS name + version,
    /// sorted with most-specific version first.
    func bootCommands(for osName: String, version: String) -> [BootCommandBlock] {
        bootCommands
            .filter { cmd in
                cmd.osName.isEmpty ||
                (cmd.osName == osName && (cmd.osVersion.isEmpty || cmd.osVersion == version))
            }
            .sorted { a, b in
                // More-specific version match sorts first
                let aSpecific = !a.osVersion.isEmpty && a.osVersion == version
                let bSpecific = !b.osVersion.isEmpty && b.osVersion == version
                if aSpecific != bSpecific { return aSpecific }
                // Base blocks after custom
                if a.isBase != b.isBase { return !a.isBase }
                return a.displayName < b.displayName
            }
    }

    // MARK: - Provisioner block API

    func add(_ block: BuildingBlock) {
        blocks.append(block)
        saveBlocks()
    }

    func update(id: UUID, _ apply: (inout BuildingBlock) -> Void) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        apply(&blocks[i])
        saveBlocks()
    }

    func delete(id: UUID) {
        blocks.removeAll { $0.id == id && !$0.isBase }
        saveBlocks()
    }

    func duplicate(_ block: BuildingBlock) -> BuildingBlock {
        let copy = BuildingBlock(
            displayName: "\(block.displayName) (Copy)",
            blockDescription: block.blockDescription,
            provisioner: block.provisioner,
            hclContent: block.hclContent,
            isBase: false,
            createdAt: Date(),
            osName: block.osName,
            osVersion: block.osVersion
        )
        add(copy)
        return copy
    }

    // MARK: - Boot command block API

    func addBootCommand(_ cmd: BootCommandBlock) {
        bootCommands.append(cmd)
        saveBootCommands()
    }

    func updateBootCommand(id: UUID, _ apply: (inout BootCommandBlock) -> Void) {
        guard let i = bootCommands.firstIndex(where: { $0.id == id }) else { return }
        apply(&bootCommands[i])
        saveBootCommands()
    }

    func deleteBootCommand(id: UUID) {
        bootCommands.removeAll { $0.id == id && !$0.isBase }
        saveBootCommands()
    }

    func duplicateBootCommand(_ cmd: BootCommandBlock) -> BootCommandBlock {
        let copy = BootCommandBlock(
            displayName: "\(cmd.displayName) (Copy)",
            blockDescription: cmd.blockDescription,
            commandLines: cmd.commandLines,
            isBase: false,
            createdAt: Date(),
            osName: cmd.osName,
            osVersion: cmd.osVersion
        )
        addBootCommand(copy)
        return copy
    }

    func bootCommand(id: UUID) -> BootCommandBlock? {
        bootCommands.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        // Provisioner blocks
        let storedBlocks: [BuildingBlock] = AppDatabase.shared.readOrDefault(.packerBlocks, default: [])
        let baseBlockIDs = Set(BuildingBlock.baseBlocks.map(\.id))
        let customBlocksFromStorage = storedBlocks.filter { !baseBlockIDs.contains($0.id) && !$0.isBase }
        blocks = BuildingBlock.baseBlocks + customBlocksFromStorage

        // Boot command blocks
        let storedCmds: [BootCommandBlock] = AppDatabase.shared.readOrDefault(.packerBootCommands, default: [])
        let baseCmdIDs = Set(BootCommandBlock.baseBlocks.map(\.id))
        let customCmdsFromStorage = storedCmds.filter { !baseCmdIDs.contains($0.id) && !$0.isBase }
        bootCommands = BootCommandBlock.baseBlocks + customCmdsFromStorage
    }

    private func saveBlocks() {
        AppDatabase.shared.writeSilently(customBlocks, to: .packerBlocks)
    }

    private func saveBootCommands() {
        AppDatabase.shared.writeSilently(customBootCommands, to: .packerBootCommands)
    }
}
