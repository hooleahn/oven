import SwiftUI

// MARK: - BaseVMViewModel

@MainActor
@Observable
final class BaseVMViewModel {

    var selectedBaseVMID: UUID?
    var isPresentingNewSheet = false
    var createVMFromBase: VirtualMachine?
    var confirmDelete: VirtualMachine?

    // Context menu / detail pane actions lifted so the list can trigger them
    var editingBaseVM: VirtualMachine?          = nil
    var showBuildLogForBaseVM: VirtualMachine?  = nil
    var pushToRegistryBaseVM: VirtualMachine?   = nil

    // MARK: - Derived

    func selectedBaseVM(from baseVMs: [VirtualMachine]) -> VirtualMachine? {
        guard let id = selectedBaseVMID else { return nil }
        return baseVMs.first { $0.id == id }
    }

    // MARK: - Actions

    func delete(_ baseVM: VirtualMachine, from baseVMStore: BaseVMStore) async {
        if selectedBaseVMID == baseVM.id { selectedBaseVMID = nil }
        await baseVMStore.delete(id: baseVM.id)
    }
}
