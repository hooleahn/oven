import SwiftUI

// MARK: - BuildingBlockStore

@MainActor
@Observable
final class BuildingBlockStore: ObservableObject {

    private(set) var blocks: [BuildingBlock] = []

    init() { load() }

    // MARK: - Computed

    var baseBlocks: [BuildingBlock]   { blocks.filter {  $0.isBase } }
    var customBlocks: [BuildingBlock] { blocks.filter { !$0.isBase } }

    // MARK: - Public API

    func add(_ block: BuildingBlock) {
        blocks.append(block)
        save()
    }

    func update(id: UUID, _ apply: (inout BuildingBlock) -> Void) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        apply(&blocks[i])
        save()
    }

    func delete(id: UUID) {
        blocks.removeAll { $0.id == id && !$0.isBase }
        save()
    }

    func duplicate(_ block: BuildingBlock) -> BuildingBlock {
        var copy = block
        copy = BuildingBlock(
            displayName: "\(block.displayName) (Copy)",
            blockDescription: block.blockDescription,
            provisioner: block.provisioner,
            hclContent: block.hclContent,
            isBase: false,
            createdAt: Date()
        )
        add(copy)
        return copy
    }

    // MARK: - Persistence

    private func load() {
        let stored: [BuildingBlock] = AppDatabase.shared.readOrDefault(.packerBlocks, default: [])
        // Merge: always show all seeded base blocks (in case new ones were added in an update),
        // then append user custom blocks from storage.
        let baseIDs = Set(BuildingBlock.baseBlocks.map(\.id))
        let customFromStorage = stored.filter { !baseIDs.contains($0.id) && !$0.isBase }
        blocks = BuildingBlock.baseBlocks + customFromStorage
    }

    private func save() {
        // Only persist custom blocks — base blocks are always re-seeded from code.
        AppDatabase.shared.writeSilently(customBlocks, to: .packerBlocks)
    }
}
