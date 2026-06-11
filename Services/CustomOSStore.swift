import Foundation

@MainActor
@Observable
final class CustomOSStore {

    var entries: [CustomOSEntry] = []

    init() { load() }

    func load() {
        entries = AppDatabase.shared.readOrDefault(.customOS, default: [])
    }

    func add(_ entry: CustomOSEntry) {
        guard !entries.contains(where: {
            $0.releaseName.lowercased() == entry.releaseName.lowercased()
            && $0.majorVersion == entry.majorVersion
        }) else { return }
        entries.append(entry)
        save()
    }

    /// Create or find a matching entry and return it.
    @discardableResult
    func findOrCreate(releaseName: String, majorVersion: Int) -> CustomOSEntry {
        let trimmed = releaseName.trimmingCharacters(in: .whitespaces)
        if let existing = entries.first(where: {
            $0.releaseName.lowercased() == trimmed.lowercased()
            && $0.majorVersion == majorVersion
        }) { return existing }
        let entry = CustomOSEntry(releaseName: trimmed, majorVersion: majorVersion)
        entries.append(entry)
        save()
        return entry
    }

    func delete(_ entry: CustomOSEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func save() {
        AppDatabase.shared.writeSilently(entries, to: .customOS)
    }
}
