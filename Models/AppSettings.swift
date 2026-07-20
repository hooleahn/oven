import Foundation

struct AppSettings: Codable {
    var vmStorageRoot: URL
    var ipswStorageRoot: URL
    var packerTemplatesRoot: URL
    var depsRoot: URL
    var tartHome: String?   // nil = use TART_HOME env var or ~/.tart default
    var ipswDownloadMode: IPSWDownloadMode = .ipswMe
    var mistIncludeBetas: Bool = false

    // Per-dependency install configuration (replaces legacy dependencyMode/customPaths)
    var dependencySettings: [String: DependencyInstallSetting] = [:]

    // Legacy — retained so old settings round-trip; logic has moved to dependencySettings
    var dependencyMode: DependencyMode = .managed
    var customPaths: CustomBinaryPaths = CustomBinaryPaths()

    // MARK: - Per-dependency install setting

    struct DependencyInstallSetting: Codable, Equatable, Sendable {
        enum Method: String, Codable, CaseIterable, Sendable {
            case managed  // Oven downloads and updates the binary
            case custom   // User-specified path (includes detected system binaries)
        }
        var method: Method = .managed
        var customPath: String = ""
    }

    func setting(for id: String) -> DependencyInstallSetting {
        dependencySettings[id] ?? DependencyInstallSetting()
    }

    /// Returns the effective binary path for `id` when the user has selected a custom path.
    /// Returns nil if the dependency is in managed mode or has no custom path configured.
    func effectivePath(for id: String) -> String? {
        let s = setting(for: id)
        guard s.method == .custom, !s.customPath.isEmpty else { return nil }
        return s.customPath
    }

    // MARK: - Legacy types (kept for migration)

    enum IPSWDownloadMode: String, Codable {
        case ipswMe  = "ipsw_me"
        case mistCli = "mist_cli"
    }

    enum DependencyMode: String, Codable {
        case managed
        case custom
    }

    struct CustomBinaryPaths: Codable {
        var tart: String = ""
        var packer: String = ""
        var mistCli: String = ""
        var jq: String = ""
        var sshpass: String = ""

        enum CodingKeys: String, CodingKey {
            case tart, packer, mistCli = "mist-cli", jq, sshpass
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tart    = (try? c.decodeIfPresent(String.self, forKey: .tart))    ?? ""
            packer  = (try? c.decodeIfPresent(String.self, forKey: .packer))  ?? ""
            mistCli = (try? c.decodeIfPresent(String.self, forKey: .mistCli)) ?? ""
            jq      = (try? c.decodeIfPresent(String.self, forKey: .jq))      ?? ""
            sshpass = (try? c.decodeIfPresent(String.self, forKey: .sshpass)) ?? ""
        }
    }

    // MARK: - Defaults and storage

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
        if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        Task { await AppLogger.shared.log("app-settings.json could not be decoded — resetting to defaults", source: "AppSettings") }
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

    func checkTartHomeAccessibility() -> String? {
        let url = resolvedTartHome
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return "The TART_HOME directory \"\(url.path)\" does not exist. The storage volume may be disconnected. Switch to a different profile in Preferences \u{2192} Profiles."
        }
        guard isDir.boolValue else {
            return "The TART_HOME path \"\(url.path)\" is not a directory. Switch to a different profile in Preferences \u{2192} Profiles."
        }
        guard fm.isReadableFile(atPath: url.path) else {
            return "The TART_HOME directory \"\(url.path)\" is not readable. Check that the volume is mounted and accessible."
        }
        guard fm.isWritableFile(atPath: url.path) else {
            return "The TART_HOME directory \"\(url.path)\" is not writable. Check volume permissions or switch to a different profile in Preferences \u{2192} Profiles."
        }
        return nil
    }

    // MARK: - Explicit memberwise init

    init(vmStorageRoot: URL, ipswStorageRoot: URL, packerTemplatesRoot: URL,
         depsRoot: URL, tartHome: String? = nil,
         ipswDownloadMode: IPSWDownloadMode = .ipswMe,
         mistIncludeBetas: Bool = false,
         dependencySettings: [String: DependencyInstallSetting] = [:],
         dependencyMode: DependencyMode = .managed,
         customPaths: CustomBinaryPaths = CustomBinaryPaths()) {
        self.vmStorageRoot       = vmStorageRoot
        self.ipswStorageRoot     = ipswStorageRoot
        self.packerTemplatesRoot = packerTemplatesRoot
        self.depsRoot            = depsRoot
        self.tartHome            = tartHome
        self.ipswDownloadMode    = ipswDownloadMode
        self.mistIncludeBetas    = mistIncludeBetas
        self.dependencySettings  = dependencySettings
        self.dependencyMode      = dependencyMode
        self.customPaths         = customPaths
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case vmStorageRoot, ipswStorageRoot, packerTemplatesRoot, depsRoot, tartHome, ipswDownloadMode
        case mistIncludeBetas
        case dependencySettings
        // Legacy keys — decoded for migration only
        case dependencyMode, customPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let root = AppSettings.defaultLocalStorageRoot
        vmStorageRoot       = (try? c.decodeIfPresent(URL.self, forKey: .vmStorageRoot))       ?? root.appendingPathComponent("tart-vms")
        ipswStorageRoot     = (try? c.decodeIfPresent(URL.self, forKey: .ipswStorageRoot))     ?? root.appendingPathComponent("ipsws")
        packerTemplatesRoot = (try? c.decodeIfPresent(URL.self, forKey: .packerTemplatesRoot)) ?? root.appendingPathComponent("packer-templates")
        depsRoot            = (try? c.decodeIfPresent(URL.self, forKey: .depsRoot))            ?? root.appendingPathComponent("deps")
        tartHome            = try? c.decodeIfPresent(String.self, forKey: .tartHome)
        ipswDownloadMode    = (try? c.decodeIfPresent(IPSWDownloadMode.self, forKey: .ipswDownloadMode)) ?? .ipswMe
        mistIncludeBetas    = (try? c.decodeIfPresent(Bool.self, forKey: .mistIncludeBetas)) ?? false
        dependencyMode      = (try? c.decodeIfPresent(DependencyMode.self, forKey: .dependencyMode)) ?? .managed
        customPaths         = (try? c.decodeIfPresent(CustomBinaryPaths.self, forKey: .customPaths)) ?? CustomBinaryPaths()

        // Per-dependency settings — migrate from legacy global format if absent
        let savedDepSettings = (try? c.decodeIfPresent([String: DependencyInstallSetting].self, forKey: .dependencySettings)) ?? [:]
        if savedDepSettings.isEmpty, dependencyMode == .custom {
            var migrated: [String: DependencyInstallSetting] = [:]
            let pairs: [(String, String)] = [
                ("tart", customPaths.tart), ("packer", customPaths.packer),
                ("mist-cli", customPaths.mistCli), ("jq", customPaths.jq), ("sshpass", customPaths.sshpass)
            ]
            for (id, path) in pairs where !path.isEmpty {
                migrated[id] = DependencyInstallSetting(method: .custom, customPath: path)
            }
            dependencySettings = migrated
        } else {
            dependencySettings = savedDepSettings
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.defaultLocalStorageRoot, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.settingsURL, options: .atomic)
    }
}
