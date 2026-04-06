import Foundation

struct AppSettings: Codable {
    var vmStorageRoot: URL
    var ipswStorageRoot: URL
    var packerTemplatesRoot: URL
    var depsRoot: URL
    var tartHome: String?   // nil = use TART_HOME env var or ~/.tart default
    var ipswDownloadMode: IPSWDownloadMode = .ipswMe

    enum IPSWDownloadMode: String, Codable {
        case ipswMe  = "ipsw_me"   // default: direct from ipsw.me API
        case mistCli = "mist_cli"  // use mist-cli (must be installed)
    }

    static var defaultLocalStorageRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Oven", isDirectory: true)
    }

    static var `default`: AppSettings {
        let root = defaultLocalStorageRoot
        return AppSettings(
            vmStorageRoot:       root.appendingPathComponent("tart-vms", isDirectory: true),
            ipswStorageRoot:     root.appendingPathComponent("ipsws", isDirectory: true),
            packerTemplatesRoot: root.appendingPathComponent("packer-templates", isDirectory: true),
            depsRoot:            root.appendingPathComponent("deps", isDirectory: true),
            tartHome:            nil,
            ipswDownloadMode:    .ipswMe
        )
    }

    private static var settingsURL: URL {
        defaultLocalStorageRoot.appendingPathComponent("app-settings.json")
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return .default }
        let decoder = JSONDecoder()
        if let settings = try? decoder.decode(AppSettings.self, from: data) {
            return settings
        }
        // Decode failed — new field likely added; fall back to defaults
        return .default
    }

    /// Resolved TART_HOME: user setting → TART_HOME env var → ~/.tart
    var resolvedTartHome: URL {
        if let set = tartHome, !set.isEmpty {
            return URL(fileURLWithPath: set, isDirectory: true)
        }
        if let env = ProcessInfo.processInfo.environment["TART_HOME"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tart", isDirectory: true)
    }

    // Explicit memberwise init (required once we define a custom Decodable init)
    init(vmStorageRoot: URL, ipswStorageRoot: URL, packerTemplatesRoot: URL,
         depsRoot: URL, tartHome: String? = nil,
         ipswDownloadMode: IPSWDownloadMode = .ipswMe) {
        self.vmStorageRoot       = vmStorageRoot
        self.ipswStorageRoot     = ipswStorageRoot
        self.packerTemplatesRoot = packerTemplatesRoot
        self.depsRoot            = depsRoot
        self.tartHome            = tartHome
        self.ipswDownloadMode    = ipswDownloadMode
    }

    // CodingKeys for custom Decodable init
    enum CodingKeys: String, CodingKey {
        case vmStorageRoot, ipswStorageRoot, packerTemplatesRoot, depsRoot, tartHome, ipswDownloadMode
    }

    // Custom Decodable so new fields added in future builds don't wipe existing settings
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let root = AppSettings.defaultLocalStorageRoot
        vmStorageRoot       = (try? c.decodeIfPresent(URL.self, forKey: .vmStorageRoot))       ?? root.appendingPathComponent("tart-vms")
        ipswStorageRoot     = (try? c.decodeIfPresent(URL.self, forKey: .ipswStorageRoot))     ?? root.appendingPathComponent("ipsws")
        packerTemplatesRoot = (try? c.decodeIfPresent(URL.self, forKey: .packerTemplatesRoot)) ?? root.appendingPathComponent("packer-templates")
        depsRoot            = (try? c.decodeIfPresent(URL.self, forKey: .depsRoot))            ?? root.appendingPathComponent("deps")
        tartHome            = try? c.decodeIfPresent(String.self, forKey: .tartHome)
        ipswDownloadMode    = (try? c.decodeIfPresent(IPSWDownloadMode.self, forKey: .ipswDownloadMode)) ?? .ipswMe
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.defaultLocalStorageRoot, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.settingsURL, options: .atomic)
    }
}
