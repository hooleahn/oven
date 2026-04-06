import SwiftUI

@MainActor
@Observable
final class AppState: ObservableObject {

    // Navigation
    var activeSheet: AppSheet?
    var searchQuery: String = ""

    // New VM / Base VM sheet triggers
    var isPresentingNewVM = false
    var isPresentingNewBaseVM = false

    // Active operations (for progress display)
    var activeOperations: [OperationRecord] = []

    // Registry pull progress — keyed by imageRef, survives sidebar navigation
    var registryDownloads: [String: Double] = [:]
    var activeIPSWDownloads: [String: Double] = [:]  // buildid → progress

    // MARK: - Operation tracking

    struct OperationRecord: Identifiable {
        let id = UUID()
        let vmName: String
        let kind: Kind
        var logLines: [String] = []
        var isFinished = false

        enum Kind: String {
            case clone    = "Cloning"
            case start    = "Starting"
            case stop     = "Stopping"
            case delete   = "Deleting"
            case pull     = "Pulling"
        }
    }

    func beginOperation(vmName: String, kind: OperationRecord.Kind) -> UUID {
        let record = OperationRecord(vmName: vmName, kind: kind)
        activeOperations.append(record)
        return record.id
    }

    func appendLog(operationID: UUID, line: String) {
        guard let idx = activeOperations.firstIndex(where: { $0.id == operationID }) else { return }
        activeOperations[idx].logLines.append(line)
    }

    func finishOperation(id: UUID) {
        guard let idx = activeOperations.firstIndex(where: { $0.id == id }) else { return }
        activeOperations[idx].isFinished = true
        // Auto-remove after a short delay so the UI can show a done state
        Task {
            try? await Task.sleep(for: .seconds(3))
            activeOperations.removeAll { $0.id == id }
        }
    }
}

// MARK: - Sheet identifiers

enum AppSheet: Identifiable {
    case newVM
    case newBaseVM
    case newMDMProfile
    case editBaseVM(id: UUID)
    case editMDMProfile(id: UUID)
    case storageSettings

    var id: String {
        switch self {
        case .newVM:                  return "newVM"
        case .newBaseVM:              return "newBaseVM"
        case .newMDMProfile:          return "newMDMProfile"
        case .editBaseVM(let id):     return "editBaseVM-\(id)"
        case .editMDMProfile(let id): return "editMDMProfile-\(id)"
        case .storageSettings:        return "storageSettings"
        }
    }
}
