import Foundation

struct OvenProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// Overrides TART_HOME. nil = use AppSettings default (env var or ~/.tart).
    var tartHome: String?
    /// Overrides where IPSW firmware files are stored. nil = platform default.
    var ipswStorageRoot: URL?
    /// Overrides where Packer templates are stored. nil = platform default.
    var packerTemplatesRoot: URL?
    /// Root directory where this profile's Oven metadata JSON files are stored.
    var metadataRoot: URL

    var resolvedIPSWRoot: URL {
        ipswStorageRoot ?? AppSettings.default.ipswStorageRoot
    }

    var resolvedPackerTemplatesRoot: URL {
        packerTemplatesRoot ?? AppSettings.default.packerTemplatesRoot
    }

    /// Returns a "Default" profile mirroring the current AppSettings.
    /// Uses the global metadata root so existing data is preserved on first run.
    static func makeDefault() -> OvenProfile {
        let settings  = AppSettings.load()
        let defaults  = AppSettings.default
        return OvenProfile(
            id: UUID(),
            name: "Default",
            tartHome: settings.tartHome,
            ipswStorageRoot: settings.ipswStorageRoot != defaults.ipswStorageRoot
                ? settings.ipswStorageRoot : nil,
            packerTemplatesRoot: settings.packerTemplatesRoot != defaults.packerTemplatesRoot
                ? settings.packerTemplatesRoot : nil,
            metadataRoot: AppSettings.defaultLocalStorageRoot
        )
    }
}
