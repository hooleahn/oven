import Foundation

@MainActor
@Observable
final class ProfileStore {

    private(set) var profiles: [OvenProfile]
    private(set) var activeProfileID: UUID

    var activeProfile: OvenProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    private static var profilesURL: URL {
        AppSettings.defaultLocalStorageRoot.appendingPathComponent("profiles.json")
    }
    private static let activeProfileKey = "com.oven.activeProfileID"

    // MARK: - Init

    init() {
        var loaded = Self.loadFromDisk()
        if loaded.isEmpty {
            loaded = [OvenProfile.makeDefault()]
        }
        profiles = loaded

        let storedID = UserDefaults.standard.string(forKey: Self.activeProfileKey).flatMap(UUID.init)
        let validID  = storedID.flatMap { id in loaded.contains(where: { $0.id == id }) ? id : nil }
        activeProfileID = validID ?? loaded[0].id

        // Apply the active profile's metadata root so any stores initialised after
        // this point read from the correct directory.
        let active = loaded.first { $0.id == activeProfileID } ?? loaded[0]
        AppDatabase.shared.switchRoot(to: active.metadataRoot)
    }

    // MARK: - Bootstrap

    /// Applies the persisted active profile's metadata root to AppDatabase.
    /// Called from OvenApp.init() before any @State store is initialised.
    static func bootstrapActiveProfile() {
        let loaded = loadFromDisk()
        guard !loaded.isEmpty else { return }
        let storedID = UserDefaults.standard.string(forKey: activeProfileKey).flatMap(UUID.init)
        let active   = loaded.first { $0.id == storedID } ?? loaded[0]
        AppDatabase.shared.switchRoot(to: active.metadataRoot)
    }

    // MARK: - CRUD

    @discardableResult
    func addProfile(name: String, tartHome: String?) -> OvenProfile {
        let profileDir = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("profiles/\(UUID().uuidString)", isDirectory: true)
        let profile = OvenProfile(id: UUID(), name: name, tartHome: tartHome, metadataRoot: profileDir)
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            switchToProfile(id: profiles[0].id)
        } else {
            saveProfiles()
        }
    }

    func rename(id: UUID, to name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        saveProfiles()
    }

    func setTartHome(id: UUID, to tartHome: String?) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].tartHome = tartHome
        saveProfiles()
        if activeProfileID == id {
            var settings = AppSettings.load()
            settings.tartHome = tartHome
            try? settings.save()
        }
    }

    func setIPSWRoot(id: UUID, to url: URL?) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].ipswStorageRoot = url
        saveProfiles()
        if activeProfileID == id {
            var settings = AppSettings.load()
            settings.ipswStorageRoot = url ?? AppSettings.default.ipswStorageRoot
            try? settings.save()
        }
    }

    func setPackerTemplatesRoot(id: UUID, to url: URL?) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].packerTemplatesRoot = url
        saveProfiles()
        if activeProfileID == id {
            var settings = AppSettings.load()
            settings.packerTemplatesRoot = url ?? AppSettings.default.packerTemplatesRoot
            try? settings.save()
        }
    }

    /// Activates a profile: updates AppSettings storage paths and AppDatabase root.
    /// Callers must trigger vmStore.reload() and templateStore.load() after this returns.
    func switchToProfile(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
        saveProfiles()
        var settings = AppSettings.load()
        settings.tartHome            = profile.tartHome
        settings.ipswStorageRoot     = profile.resolvedIPSWRoot
        settings.packerTemplatesRoot = profile.resolvedPackerTemplatesRoot
        try? settings.save()
        AppDatabase.shared.switchRoot(to: profile.metadataRoot)
    }

    // MARK: - Persistence

    private func saveProfiles() {
        do {
            try FileManager.default.createDirectory(
                at: AppSettings.defaultLocalStorageRoot, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: Self.profilesURL, options: .atomic)
        } catch {
            Task { await AppLogger.shared.error("Failed to save profiles: \(error)", source: "ProfileStore") }
        }
    }

    private static func loadFromDisk() -> [OvenProfile] {
        guard let data = try? Data(contentsOf: profilesURL) else { return [] }
        return (try? JSONDecoder().decode([OvenProfile].self, from: data)) ?? []
    }
}
