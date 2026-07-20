import Foundation
import CryptoKit

// MARK: - Download source

private struct ReleaseSource {
    let url: URL
    let expectedSHA256: String?
    let extraction: ExtractionMethod

    enum ExtractionMethod {
        case rawBinary
        case tarGz(binaryPath: String)
        case zip(binaryNamePrefix: String)
case pkgWithInstaller(binaryName: String) // copy binary out after expanding pkg payload
    }
}

// MARK: - DependencyManager

@MainActor
@Observable
final class DependencyManager {

    var dependencies: [Dependency] = []
    var isCheckingVersions = false
    var isCheckingForUpdates = false
    var installLog: [String] = []

    /// Last time we successfully checked for upstream updates.
    var lastUpdateCheck: Date? = nil

    private let depsDirectory: URL
    private let manifestURL: URL
    private let processRunner = ProcessRunner()
    private var updateCheckTask: Task<Void, Never>? = nil

    init(storageRoot: URL) {
        self.depsDirectory = storageRoot.appendingPathComponent("deps", isDirectory: true)
        self.manifestURL = depsDirectory.appendingPathComponent("versions.json")
        buildInitialState(settings: AppSettings.load())
    }

    // MARK: - Public API

    func bootstrap() async {
        let settings = AppSettings.load()
        buildInitialState(settings: settings)

        isCheckingVersions = true
        log("Checking dependencies…")
        AppLogger.shared.log("Checking dependencies…", source: "DependencyManager")
        try? FileManager.default.createDirectory(at: depsDirectory, withIntermediateDirectories: true)
        await detectSystemBinaries()
        await refreshStatuses()

        let alreadyReady = dependencies.filter { $0.isReady }
        for dep in alreadyReady {
            AppLogger.shared.success("\(dep.displayName) \(dep.currentVersion ?? "") already installed", source: "DependencyManager")
        }

        let missing = dependencies.filter { $0.status == .notInstalled }
        if missing.isEmpty {
            log("All dependencies ready.")
            AppLogger.shared.success("All dependencies ready", source: "DependencyManager")
        } else {
            log("Missing: \(missing.map(\.displayName).joined(separator: ", "))")
            AppLogger.shared.warning("Missing: \(missing.map(\.displayName).joined(separator: ", "))", source: "DependencyManager")
        }
        isCheckingVersions = false

        if dependencies.contains(where: { $0.installMethod == .managed && $0.id != "tart-packer-plugin" }) {
            await checkForUpdates()
            schedulePeriodicUpdateChecks()
        }
    }

    /// Re-load settings and refresh dependency state. Called when the user
    /// changes install method or custom paths in Preferences or SetupView.
    func reloadSettings() async {
        let settings = AppSettings.load()
        buildInitialState(settings: settings)
        await detectSystemBinaries()
        await refreshStatuses()

        if dependencies.contains(where: { $0.installMethod == .managed && $0.id != "tart-packer-plugin" }) {
            await checkForUpdates()
            schedulePeriodicUpdateChecks()
        } else {
            updateCheckTask?.cancel()
            updateCheckTask = nil
        }
    }

    /// Explicitly check GitHub for the latest versions of all managed tools.
    func checkForUpdates() async {
        let managedDeps = dependencies.filter { $0.installMethod == .managed && $0.id != "tart-packer-plugin" }
        guard !managedDeps.isEmpty else {
            isCheckingForUpdates = false
            return
        }
        isCheckingForUpdates = true
        AppLogger.shared.log("Checking for dependency updates…", source: "DependencyManager")
        for dep in managedDeps {
            guard let (owner, repo) = githubCoords(for: dep.id) else { continue }
            if let latest = try? await fetchLatestGitHubTag(owner: owner, repo: repo) {
                let latestVersion: String
                if let r = latest.range(of: #"\d+\.\d+[\.\d]*"#, options: .regularExpression) {
                    latestVersion = String(latest[r])
                } else {
                    latestVersion = latest
                }
                updateLatestVersion(id: dep.id, latestVersion: latestVersion)
                if let current = dependencies.first(where: { $0.id == dep.id })?.currentVersion,
                   current != latestVersion,
                   dependencies.first(where: { $0.id == dep.id })?.status == .installed {
                    updateStatus(id: dep.id, to: .updateAvailable)
                }
            }
        }
        lastUpdateCheck = Date()
        isCheckingForUpdates = false
        AppLogger.shared.log("Dependency update check complete", source: "DependencyManager")
    }

    func install(_ dependency: Dependency) async {
        log("Installing \(dependency.displayName)…")
        updateStatus(id: dependency.id, to: .installing)
        do {
            let installedPath = try await downloadAndInstall(dep: dependency)
            let version = try? await readVersion(binaryPath: installedPath, id: dependency.id)
            updateInstalledVersion(id: dependency.id, version: version ?? "installed")
            // Switch to managed and clear any custom path override
            if let i = dependencies.firstIndex(where: { $0.id == dependency.id }) {
                dependencies[i].installMethod = .managed
                dependencies[i].customPath = ""
            }
            var settings = AppSettings.load()
            settings.dependencySettings[dependency.id] = AppSettings.DependencyInstallSetting(method: .managed, customPath: "")
            try? settings.save()
            updateStatus(id: dependency.id, to: .installed)
            log("✓ \(dependency.displayName) \(version ?? "") installed.")
            AppLogger.shared.success("\(dependency.displayName) \(version ?? "") installed", source: "DependencyManager")
        } catch {
            updateStatus(id: dependency.id, to: .error)
            log("✗ \(dependency.displayName) failed: \(error.localizedDescription)")
            AppLogger.shared.error("\(dependency.displayName) install failed: \(error.localizedDescription)", source: "DependencyManager")
        }
    }

    var storageRoot: URL { depsDirectory.deletingLastPathComponent() }

    var allReady: Bool {
        dependencies
            .filter { $0.requiredForLaunch }
            .allSatisfy { $0.isReady || $0.status == .skipped }
    }

    /// Point a dependency at a user-supplied binary. Validates with `--version` before accepting.
    /// Persists the choice to AppSettings so services read the new path immediately.
    func setSystemBinary(id: String, path: URL) async {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        let version = try? await readVersion(binaryPath: path.path, id: id)
        dependencies[i].installMethod = .custom
        dependencies[i].customPath = path.path
        dependencies[i].currentVersion = version
        dependencies[i].status = version != nil ? .installed : .error
        var settings = AppSettings.load()
        settings.dependencySettings[id] = AppSettings.DependencyInstallSetting(method: .custom, customPath: path.path)
        try? settings.save()
    }

    /// Accept a previously detected system binary as the custom-path override.
    func useDetectedBinary(id: String) async {
        guard let dep = dependencies.first(where: { $0.id == id }),
              let detected = dep.detectedSystemPath else { return }
        await setSystemBinary(id: id, path: detected)
    }

    /// Change the install method for a dependency and optionally set a custom path.
    /// Persists the choice and re-evaluates the dep status.
    func setInstallMethod(id: String, to method: AppSettings.DependencyInstallSetting.Method, customPath: String = "") async {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        dependencies[i].installMethod = method
        dependencies[i].customPath = customPath

        var settings = AppSettings.load()
        settings.dependencySettings[id] = AppSettings.DependencyInstallSetting(method: method, customPath: customPath)
        try? settings.save()

        switch method {
        case .managed:
            // Re-check managed binary on disk
            let binaryPath = dependencies[i].binaryPath.path
            if FileManager.default.fileExists(atPath: binaryPath) {
                let version = try? await readVersion(binaryPath: binaryPath, id: id)
                dependencies[i].currentVersion = version
                dependencies[i].status = version != nil ? .installed : .notInstalled
            } else {
                dependencies[i].currentVersion = nil
                dependencies[i].status = .notInstalled
            }
        case .custom:
            guard !customPath.isEmpty else {
                dependencies[i].status = .notInstalled
                return
            }
            if FileManager.default.fileExists(atPath: customPath) {
                let version = try? await readVersion(binaryPath: customPath, id: id)
                dependencies[i].currentVersion = version
                dependencies[i].status = version != nil ? .installed : .error
            } else {
                dependencies[i].status = .notInstalled
            }
        }
    }

    /// Mark a dependency as skipped — the user acknowledges it won't be installed.
    func skipDependency(id: String) {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        dependencies[i].status = .skipped
    }

    /// Install all dependencies that are not yet installed (or in error state).
    func installAll() async {
        for dep in dependencies where dep.status == .notInstalled || dep.status == .error {
            await install(dep)
        }
    }

    /// For each uninstalled dependency: use the detected system binary if available,
    /// otherwise download and install Oven's managed copy.
    func installMissing() async {
        for dep in dependencies where dep.status == .notInstalled || dep.status == .error {
            if dep.detectedSystemPath != nil {
                await useDetectedBinary(id: dep.id)
            } else {
                await install(dep)
            }
        }
    }

    var hasUpdatesAvailable: Bool {
        dependencies.contains { $0.installMethod == .managed && $0.status == .updateAvailable }
    }

    func path(for id: String) throws -> String {
        if id == "tart-packer-plugin" {
            let pluginDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart", isDirectory: true)
            if let file = try? FileManager.default.contentsOfDirectory(atPath: pluginDir.path)
                .first(where: { $0.hasPrefix("packer-plugin-tart") }) {
                return pluginDir.appendingPathComponent(file).path
            }
            throw ProcessError.binaryNotFound("packer-plugin-tart not found in \(pluginDir.path)")
        }
        guard let dep = dependencies.first(where: { $0.id == id }) else {
            throw ProcessError.binaryNotFound(id)
        }
        switch dep.installMethod {
        case .custom:
            guard !dep.customPath.isEmpty else {
                throw ProcessError.binaryNotFound("\(id) — no custom path configured")
            }
            return dep.customPath
        case .managed:
            guard dep.isReady else {
                throw ProcessError.binaryNotFound("\(depsDirectory.path)/\(id)")
            }
            return dep.binaryPath.path
        }
    }

    // MARK: - System binary detection

    /// Searches well-known locations and the user's shell PATH for each dependency,
    /// storing any match in `detectedSystemPath`. Two-pass:
    ///   1. Check known fixed directories (fast, no subprocess)
    ///   2. Ask `which` with an extended PATH as a fallback
    private func detectSystemBinaries() async {
        let fm = FileManager.default
        let searchDirs = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/usr/bin",
            "/usr/sbin",
            "/bin",
        ]
        let extendedPATH = searchDirs.joined(separator: ":") + ":/sbin"

        func binaryName(for id: String) -> String? {
            switch id {
            case "tart":     return "tart"
            case "packer":   return "packer"
            case "mist-cli": return "mist"
            case "jq":       return "jq"
            case "sshpass":  return "sshpass"
            default:         return nil
            }
        }

        for i in dependencies.indices {
            let dep = dependencies[i]
            guard let name = binaryName(for: dep.id) else { continue }

            var found: String? = nil

            for dir in searchDirs {
                let candidate = "\(dir)/\(name)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
                    found = candidate
                    break
                }
            }

            if found == nil {
                if let (stdout, _) = try? await processRunner.run(
                    "/usr/bin/which", arguments: [name],
                    environment: ["PATH": extendedPATH]
                ) {
                    let whichPath = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !whichPath.isEmpty, fm.fileExists(atPath: whichPath) {
                        found = whichPath
                    }
                }
            }

            if let path = found {
                dependencies[i].detectedSystemPath = URL(fileURLWithPath: path)
                AppLogger.shared.log("Detected system \(dep.displayName) at \(path)", source: "DependencyManager")
            }
        }
    }

    // MARK: - Periodic update checks

    private func schedulePeriodicUpdateChecks() {
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12 * 60 * 60))
                guard !Task.isCancelled else { break }
                await self?.checkForUpdates()
            }
        }
    }

    // MARK: - GitHub coordinate map

    private func githubCoords(for id: String) -> (owner: String, repo: String)? {
        switch id {
        case "tart":     return ("cirruslabs", "tart")
        case "packer":   return ("hashicorp", "packer")
        case "mist-cli": return ("ninxsoft", "mist-cli")
        case "jq":       return ("jqlang", "jq")
        default:         return nil
        }
    }

    // MARK: - Per-tool install logic

    private func downloadAndInstall(dep: Dependency) async throws -> String {
        switch dep.id {

        // ── tart ──────────────────────────────────────────────────────────────
        case "tart":
            let tag = try await fetchLatestGitHubTag(owner: "cirruslabs", repo: "tart")
            let url = URL(string: "https://github.com/cirruslabs/tart/releases/download/\(tag)/tart.tar.gz")!
            log("  Downloading tart \(tag)…")
            let downloaded = try await download(from: url)
            let extractDir = makeTempDir()
            try runSync("/usr/bin/tar", args: ["-xzf", downloaded.path, "-C", extractDir.path])
            let binary = extractDir.appendingPathComponent("tart.app/Contents/MacOS/tart")
            guard FileManager.default.fileExists(atPath: binary.path) else {
                throw ProcessError.launchFailed("tart binary not found inside tar.gz at expected path")
            }
            let appSrc = extractDir.appendingPathComponent("tart.app")
            let appDest = depsDirectory.appendingPathComponent("tart.app")
            try? FileManager.default.removeItem(at: appDest)
            try FileManager.default.copyItem(at: appSrc, to: appDest)
            let tartBinary = appDest.appendingPathComponent("Contents/MacOS/tart")
            try setExecutable(tartBinary)
            let symlink = depsDirectory.appendingPathComponent("tart")
            try? FileManager.default.removeItem(at: symlink)
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: tartBinary)
            return tartBinary.path

        // ── packer ───────────────────────────────────────────────────────────
        case "packer":
            let tag = try await fetchLatestGitHubTag(owner: "hashicorp", repo: "packer")
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let url = URL(string: "https://releases.hashicorp.com/packer/\(version)/packer_\(version)_darwin_arm64.zip")!
            log("  Downloading packer \(version)…")
            let downloaded = try await download(from: url)
            let extractDir = makeTempDir()
            try runSync("/usr/bin/unzip", args: ["-o", downloaded.path, "-d", extractDir.path])
            let binary = try findFile(named: "packer", in: extractDir, exact: true)
            let dest = depsDirectory.appendingPathComponent("packer")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: binary, to: dest)
            try setExecutable(dest)
            return dest.path

        // ── mist-cli ──────────────────────────────────────────────────────────
        case "mist-cli":
            let tag = try await fetchLatestGitHubTag(owner: "ninxsoft", repo: "mist-cli")
            let pkgURL = try await fetchGitHubAssetURL(
                owner: "ninxsoft", repo: "mist-cli", tag: tag,
                matching: { $0.hasSuffix(".pkg") }
            )
            log("  Downloading mist-cli \(tag)…")
            let downloaded = try await download(from: pkgURL)

            let expandDir = makeTempDir()
            try runSync("/usr/bin/xar", args: ["-xf", downloaded.path, "-C", expandDir.path])

            let payloadURL = try findFile(named: "Payload", in: expandDir, exact: true)
            let cpioDir = makeTempDir()
            let gunzip = Process()
            gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            gunzip.arguments = ["-c", payloadURL.path]
            let cpio = Process()
            cpio.executableURL = URL(fileURLWithPath: "/usr/bin/cpio")
            cpio.arguments = ["-id"]
            cpio.currentDirectoryURL = cpioDir
            let pipe = Pipe()
            gunzip.standardOutput = pipe
            cpio.standardInput = pipe
            try gunzip.run()
            try cpio.run()
            gunzip.waitUntilExit()
            cpio.waitUntilExit()
            guard gunzip.terminationStatus == 0 else {
                throw ProcessError.nonZeroExit(gunzip.terminationStatus, "gunzip failed — mist-cli download may be corrupt")
            }
            guard cpio.terminationStatus == 0 else {
                throw ProcessError.nonZeroExit(cpio.terminationStatus, "cpio extraction failed")
            }

            let binary = try findFile(named: "mist", in: cpioDir, exact: true)
            let dest = depsDirectory.appendingPathComponent("mist-cli")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: binary, to: dest)
            try setExecutable(dest)
            return dest.path

        // ── packer-plugin-tart ────────────────────────────────────────────────
        case "tart-packer-plugin":
            let tag = try await fetchLatestGitHubTag(owner: "cirruslabs", repo: "packer-plugin-tart")
            let version = tag.hasPrefix("v") ? tag : "v\(tag)"
            let binaryName = "packer-plugin-tart_\(version)_x5.0_darwin_arm64"
            let assetName = "\(binaryName).zip"

            log("  Downloading packer-plugin-tart \(version)…")
            let assetURL = try await fetchGitHubAssetURL(
                owner: "cirruslabs", repo: "packer-plugin-tart", tag: tag,
                matching: { $0 == assetName }
            )
            let downloaded = try await download(from: assetURL)
            let extractDir = makeTempDir()
            try runSync("/usr/bin/unzip", args: ["-o", downloaded.path, "-d", extractDir.path])
            let binary = try findFile(named: binaryName, in: extractDir, exact: true)

            let pluginDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart", isDirectory: true)
            try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

            let dest = pluginDir.appendingPathComponent(binaryName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: binary, to: dest)
            try setExecutable(dest)
            return dest.path

        // ── jq ────────────────────────────────────────────────────────────────
        case "jq":
            let tag = try await fetchLatestGitHubTag(owner: "jqlang", repo: "jq")
            let url = URL(string: "https://github.com/jqlang/jq/releases/download/\(tag)/jq-macos-arm64")!
            log("  Downloading jq \(tag)…")
            let downloaded = try await download(from: url)
            let dest = depsDirectory.appendingPathComponent("jq")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: downloaded, to: dest)
            try setExecutable(dest)
            return dest.path

        default:
            throw ProcessError.binaryNotFound("No install logic for \(dep.id)")
        }
    }

    // MARK: - GitHub API

    private func fetchLatestGitHubTag(owner: String, repo: String) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct R: Decodable { let tagName: String; enum CodingKeys: String, CodingKey { case tagName = "tag_name" } }
        return try JSONDecoder().decode(R.self, from: data).tagName
    }

    private func fetchGitHubAssetURL(owner: String, repo: String, tag: String,
                                      matching predicate: (String) -> Bool) async throws -> URL {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(tag)")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Asset: Decodable { let name: String; let browserDownloadUrl: String
            enum CodingKeys: String, CodingKey { case name; case browserDownloadUrl = "browser_download_url" } }
        struct Release: Decodable { let assets: [Asset] }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let asset = release.assets.first(where: { predicate($0.name) }),
              let url = URL(string: asset.browserDownloadUrl) else {
            throw ProcessError.launchFailed("No matching asset found in \(owner)/\(repo) \(tag)")
        }
        return url
    }

    // MARK: - Process helpers

    private func runSync(_ executable: String, args: [String], env: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let env = env {
            var merged = ProcessInfo.processInfo.environment
            env.forEach { merged[$0] = $1 }
            process.environment = merged
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProcessError.nonZeroExit(process.terminationStatus,
                                           "\(URL(fileURLWithPath: executable).lastPathComponent) exited \(process.terminationStatus)")
        }
    }

    private func download(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ProcessError.launchFailed("HTTP \(http.statusCode) downloading \(url.lastPathComponent)")
        }
        return tempURL
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func findFile(named name: String, in dir: URL, exact: Bool) throws -> URL {
        let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let filename = url.lastPathComponent
            guard (exact ? filename == name : filename.hasPrefix(name)) else { continue }
            let vals = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if vals?.isRegularFile == true { return url }
        }
        throw ProcessError.launchFailed("'\(name)' not found in \(dir.lastPathComponent)")
    }

    private func setExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // MARK: - Version reading

    private func readVersion(binaryPath: String, id: String) async throws -> String {
        let flag: String
        switch id {
        case "packer":  flag = "version"
        case "sshpass": flag = "-V"
        default:        flag = "--version"
        }
        let (stdout, stderr) = try await processRunner.run(binaryPath, arguments: [flag])
        let output = stdout.isEmpty ? stderr : stdout
        let first = output.components(separatedBy: .newlines).first ?? output
        if let r = first.range(of: #"(\d+\.\d+[\.\d]*)"#, options: .regularExpression) {
            return String(first[r])
        }
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - State

    private struct DepMeta {
        let purpose: String
        let icon: String
        let requiredForLaunch: Bool
        let installURL: URL?
    }

    private func meta(for id: String) -> DepMeta {
        switch id {
        case "tart":
            return DepMeta(
                purpose: "Runs macOS virtual machines on Apple Silicon",
                icon: "desktopcomputer",
                requiredForLaunch: true,
                installURL: URL(string: "https://github.com/cirruslabs/tart/releases")
            )
        case "packer":
            return DepMeta(
                purpose: "Automates VM provisioning from templates",
                icon: "wrench.and.screwdriver",
                requiredForLaunch: true,
                installURL: URL(string: "https://github.com/hashicorp/packer/releases")
            )
        case "mist-cli":
            return DepMeta(
                purpose: "Downloads macOS installers from Apple's servers",
                icon: "arrow.down.circle",
                requiredForLaunch: false,
                installURL: URL(string: "https://github.com/ninxsoft/mist-cli/releases")
            )
        case "tart-packer-plugin":
            return DepMeta(
                purpose: "Packer plugin that drives tart to build VMs",
                icon: "puzzlepiece.extension",
                requiredForLaunch: true,
                installURL: URL(string: "https://github.com/cirruslabs/packer-plugin-tart/releases")
            )
        case "jq":
            return DepMeta(
                purpose: "Parses JSON output from tart and other tools",
                icon: "curlybraces",
                requiredForLaunch: true,
                installURL: URL(string: "https://github.com/jqlang/jq/releases")
            )
        case "sshpass":
            return DepMeta(
                purpose: "Non-interactive SSH password provider for executing remote commands on VMs",
                icon: "key.horizontal",
                requiredForLaunch: false,
                installURL: URL(string: "https://formulae.brew.sh/formula/sshpass")
            )
        default:
            return DepMeta(purpose: "", icon: "wrench", requiredForLaunch: false, installURL: nil)
        }
    }

    private func buildInitialState(settings: AppSettings) {
        // Preserve detection results across rebuilds
        let prevDetected: [String: URL] = dependencies.reduce(into: [:]) { dict, dep in
            if let p = dep.detectedSystemPath { dict[dep.id] = p }
        }

        func pluginInstalled() -> Dependency.Status {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return files.contains(where: { $0.hasPrefix("packer-plugin-tart") }) ? .installed : .notInstalled
        }

        let m = loadManifest()

        func st(_ id: String, _ ver: String?) -> Dependency.Status {
            ver != nil && fileExists(id) ? .installed : .notInstalled
        }

        /// Build a Dependency, overlaying the per-dep install setting from AppSettings.
        func makeDep(_ id: String, _ displayName: String, currentVersion: String?,
                     binaryPath: URL, isRequired: Bool,
                     managedStatus: Dependency.Status) -> Dependency {
            let info = meta(for: id)
            let depSetting = settings.setting(for: id)

            var status: Dependency.Status
            var version: String? = currentVersion
            switch depSetting.method {
            case .custom:
                let exists = !depSetting.customPath.isEmpty && FileManager.default.fileExists(atPath: depSetting.customPath)
                status = exists ? .installed : .notInstalled
                if !exists { version = nil }
            case .managed:
                status = managedStatus
            }

            return Dependency(id: id, displayName: displayName,
                              purpose: info.purpose, icon: info.icon,
                              currentVersion: version, latestVersion: nil,
                              binaryPath: binaryPath,
                              isRequired: isRequired, requiredForLaunch: info.requiredForLaunch,
                              installURL: info.installURL,
                              installMethod: depSetting.method,
                              customPath: depSetting.customPath,
                              detectedSystemPath: nil,
                              status: status)
        }

        // sshpass: in managed mode, check known system locations (not auto-downloaded)
        let sshpassCandidates = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass", "/opt/local/bin/sshpass",
                                  depsDirectory.appendingPathComponent("sshpass").path]
        let sshpassFoundAt = sshpassCandidates.first { FileManager.default.fileExists(atPath: $0) }
        let sshpassBinaryURL = sshpassFoundAt.map { URL(fileURLWithPath: $0) }
            ?? depsDirectory.appendingPathComponent("sshpass")
        let sshpassManagedStatus: Dependency.Status = sshpassFoundAt != nil ? .installed : .notInstalled

        // packer-plugin-tart: always installed at fixed location; custom path optional
        let pluginInfo = meta(for: "tart-packer-plugin")
        let pluginSetting = settings.setting(for: "tart-packer-plugin")
        let pluginStatus: Dependency.Status
        if pluginSetting.method == .custom, !pluginSetting.customPath.isEmpty {
            pluginStatus = FileManager.default.fileExists(atPath: pluginSetting.customPath) ? .installed : .notInstalled
        } else {
            pluginStatus = pluginInstalled()
        }

        dependencies = [
            makeDep("tart", "tart", currentVersion: m.tart,
                    binaryPath: depsDirectory.appendingPathComponent("tart.app/Contents/MacOS/tart"),
                    isRequired: true, managedStatus: st("tart", m.tart)),
            makeDep("packer", "packer", currentVersion: m.packer,
                    binaryPath: depsDirectory.appendingPathComponent("packer"),
                    isRequired: true, managedStatus: st("packer", m.packer)),
            makeDep("mist-cli", "mist-cli", currentVersion: m.mistCLI,
                    binaryPath: depsDirectory.appendingPathComponent("mist-cli"),
                    isRequired: false, managedStatus: st("mist-cli", m.mistCLI)),
            Dependency(id: "tart-packer-plugin", displayName: "packer-plugin-tart",
                       purpose: pluginInfo.purpose, icon: pluginInfo.icon,
                       currentVersion: m.tartPackerPlugin, latestVersion: nil,
                       binaryPath: depsDirectory.appendingPathComponent("tart-packer-plugin"),
                       isRequired: true, requiredForLaunch: pluginInfo.requiredForLaunch,
                       installURL: pluginInfo.installURL,
                       installMethod: pluginSetting.method,
                       customPath: pluginSetting.customPath,
                       detectedSystemPath: nil,
                       status: pluginStatus),
            makeDep("jq", "jq", currentVersion: m.jq,
                    binaryPath: depsDirectory.appendingPathComponent("jq"),
                    isRequired: true, managedStatus: st("jq", m.jq)),
            makeDep("sshpass", "sshpass", currentVersion: m.sshpass,
                    binaryPath: sshpassBinaryURL,
                    isRequired: false, managedStatus: sshpassManagedStatus),
        ]

        for i in dependencies.indices {
            dependencies[i].detectedSystemPath = prevDetected[dependencies[i].id]
        }
    }

    private func refreshStatuses() async {
        for dep in dependencies where dep.isReady {
            let binaryPath: String
            switch dep.installMethod {
            case .managed:
                binaryPath = dep.binaryPath.path
            case .custom:
                guard !dep.customPath.isEmpty else { continue }
                binaryPath = dep.customPath
            }
            let version = try? await readVersion(binaryPath: binaryPath, id: dep.id)
            updateInstalledVersion(id: dep.id, version: version)
        }
    }

    private func updateStatus(id: String, to status: Dependency.Status) {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        dependencies[i].status = status
    }

    private func updateInstalledVersion(id: String, version: String?) {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        dependencies[i].currentVersion = version
        if version != nil { dependencies[i].status = .installed }
        saveManifest()
    }

    private func updateLatestVersion(id: String, latestVersion: String?) {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        dependencies[i].latestVersion = latestVersion
    }

    private func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: depsDirectory.appendingPathComponent(name).path)
    }

    private func log(_ message: String) { installLog.append(message) }

    // MARK: - Manifest

    private func loadManifest() -> DepsManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let m = try? JSONDecoder().decode(DepsManifest.self, from: data) else { return DepsManifest() }
        return m
    }

    private func saveManifest() {
        var m = DepsManifest()
        for dep in dependencies {
            switch dep.id {
            case "tart":               m.tart = dep.currentVersion
            case "packer":             m.packer = dep.currentVersion
            case "mist-cli":           m.mistCLI = dep.currentVersion
            case "tart-packer-plugin": m.tartPackerPlugin = dep.currentVersion
            case "jq":                 m.jq = dep.currentVersion
            case "sshpass":            m.sshpass = dep.currentVersion
            default: break
            }
        }
        if let data = try? JSONEncoder().encode(m) { try? data.write(to: manifestURL) }
    }
}
