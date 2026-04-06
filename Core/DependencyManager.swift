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
        case packerPluginInit               // use `packer plugins install github.com/cirruslabs/tart`
        case pkgWithInstaller(binaryName: String) // copy binary out after expanding pkg payload
    }
}

// MARK: - DependencyManager

@MainActor
@Observable
final class DependencyManager: ObservableObject {

    var dependencies: [Dependency] = []
    var isCheckingVersions = false
    var installLog: [String] = []

    private let depsDirectory: URL
    private let manifestURL: URL
    private let processRunner = ProcessRunner()

    init(storageRoot: URL) {
        self.depsDirectory = storageRoot.appendingPathComponent("deps", isDirectory: true)
        self.manifestURL = depsDirectory.appendingPathComponent("versions.json")
        buildInitialState()
    }

    // MARK: - Public API

    func bootstrap() async {
        isCheckingVersions = true
        log("Checking dependencies…")
        AppLogger.shared.log("Checking dependencies…", source: "DependencyManager")
        try? FileManager.default.createDirectory(at: depsDirectory, withIntermediateDirectories: true)
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
            for dep in missing {
                await install(dep)
            }
        }
        isCheckingVersions = false
    }

    func install(_ dependency: Dependency) async {
        log("Installing \(dependency.displayName)…")
        updateStatus(id: dependency.id, to: .installing)
        do {
            let installedPath = try await downloadAndInstall(dep: dependency)
            let version = try? await readVersion(binaryPath: installedPath, id: dependency.id)
            updateInstalledVersion(id: dependency.id, version: version ?? "installed")
            updateStatus(id: dependency.id, to: .installed)
            log("✓ \(dependency.displayName) \(version ?? "") installed.")
            AppLogger.shared.success("\(dependency.displayName) \(version ?? "") installed", source: "DependencyManager")
        } catch {
            updateStatus(id: dependency.id, to: .error)
            log("✗ \(dependency.displayName) failed: \(error.localizedDescription)")
            AppLogger.shared.error("\(dependency.displayName) install failed: \(error.localizedDescription)", source: "DependencyManager")
        }
    }

    var allReady: Bool { dependencies.filter(\.isRequired).allSatisfy(\.isReady) }

    func path(for id: String) throws -> String {
        if id == "tart-packer-plugin" {
            // packer plugins install puts it here; packer finds it automatically
            let pluginDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart", isDirectory: true)
            if let file = try? FileManager.default.contentsOfDirectory(atPath: pluginDir.path)
                .first(where: { $0.hasPrefix("packer-plugin-tart") }) {
                return pluginDir.appendingPathComponent(file).path
            }
            throw ProcessError.binaryNotFound("packer-plugin-tart not found in \(pluginDir.path)")
        }
        guard let dep = dependencies.first(where: { $0.id == id }), dep.isReady else {
            throw ProcessError.binaryNotFound("\(depsDirectory.path)/\(id)")
        }
        return dep.binaryPath.path
    }

    // MARK: - Per-tool install logic

    private func downloadAndInstall(dep: Dependency) async throws -> String {
        switch dep.id {

        // ── tart ──────────────────────────────────────────────────────────────
        // Release: tart.tar.gz  →  tart.app/Contents/MacOS/tart
        case "tart":
            let tag = try await fetchLatestGitHubTag(owner: "cirruslabs", repo: "tart")
            let url = URL(string: "https://github.com/cirruslabs/tart/releases/download/\(tag)/tart.tar.gz")!
            log("  Downloading tart \(tag)…")
            let downloaded = try await download(from: url)
            let extractDir = makeTempDir()
            try runSync("/usr/bin/tar", args: ["-xzf", downloaded.path, "-C", extractDir.path])
            let binary = extractDir
                .appendingPathComponent("tart.app/Contents/MacOS/tart")
            guard FileManager.default.fileExists(atPath: binary.path) else {
                throw ProcessError.launchFailed("tart binary not found inside tar.gz at expected path")
            }
            // Copy the entire tart.app — tart requires its embedded provisioning
            // profile (.app/Contents/embedded.provisionprofile) to get the
            // Virtualization.Framework entitlements. Using the bare binary fails.
            let appSrc = extractDir.appendingPathComponent("tart.app")
            let appDest = depsDirectory.appendingPathComponent("tart.app")
            try? FileManager.default.removeItem(at: appDest)
            try FileManager.default.copyItem(at: appSrc, to: appDest)
            let tartBinary = appDest.appendingPathComponent("Contents/MacOS/tart")
            try setExecutable(tartBinary)
            // Also keep a symlink at deps/tart for compatibility
            let symlink = depsDirectory.appendingPathComponent("tart")
            try? FileManager.default.removeItem(at: symlink)
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: tartBinary)
            return tartBinary.path

        // ── packer ───────────────────────────────────────────────────────────
        // Release: packer_<ver>_darwin_arm64.zip  →  binary named "packer"
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
        // Release: mist-cli.pkg  →  use the GitHub API assets list to get the
        // exact asset URL, then expand the pkg payload manually.
        //
        // The pkg payload structure from ninxsoft/mist-cli is:
        //   Payload  (cpio archive inside the pkg)
        //     usr/local/bin/mist
        //
        // pkgutil --expand-full can fail on newer pkgs with SLA/distribution XML.
        // Instead we use: xar -x to unpack, then cpio to extract the Payload.
        case "mist-cli":
            let tag = try await fetchLatestGitHubTag(owner: "ninxsoft", repo: "mist-cli")
            // Fetch the actual asset list to find the .pkg URL
            let pkgURL = try await fetchGitHubAssetURL(
                owner: "ninxsoft", repo: "mist-cli", tag: tag,
                matching: { $0.hasSuffix(".pkg") }
            )
            log("  Downloading mist-cli \(tag)…")
            let downloaded = try await download(from: pkgURL)

            // Expand pkg with xar (built into macOS)
            let expandDir = makeTempDir()
            try runSync("/usr/bin/xar", args: ["-xf", downloaded.path, "-C", expandDir.path])

            // Find and extract the Payload cpio archive
            let payloadURL = try findFile(named: "Payload", in: expandDir, exact: true)
            let cpioDir = makeTempDir()
            // gunzip | cpio -i
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

            // Binary is at usr/local/bin/mist inside the extracted tree
            let binary = try findFile(named: "mist", in: cpioDir, exact: true)
            let dest = depsDirectory.appendingPathComponent("mist-cli")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: binary, to: dest)
            try setExecutable(dest)
            return dest.path

        // ── packer-plugin-tart ────────────────────────────────────────────────
        // The cleanest install method is `packer plugins install github.com/cirruslabs/tart`
        // which handles the naming convention, SHA verification, and plugin directory
        // placement automatically. We just need packer to already be installed first.
        case "tart-packer-plugin":
            let packerPath = depsDirectory.appendingPathComponent("packer").path
            guard FileManager.default.fileExists(atPath: packerPath) else {
                throw ProcessError.launchFailed("packer must be installed before packer-plugin-tart")
            }
            log("  Running: packer plugins install github.com/cirruslabs/tart…")
            // Set PACKER_PLUGIN_PATH to our deps dir so the plugin lands there
            try runSync(packerPath, args: ["plugins", "install", "github.com/cirruslabs/tart"],
                        env: ["HOME": FileManager.default.homeDirectoryForCurrentUser.path])
            // Return the path to wherever packer installed it
            return try path(for: "tart-packer-plugin")

        // ── jq ────────────────────────────────────────────────────────────────
        // Release: jq-macos-arm64  →  raw binary
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

    /// Fetch the browser_download_url for the first asset whose name matches the predicate.
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
        let flag = id == "packer" ? "version" : "--version"
        let (stdout, _) = try await processRunner.run(binaryPath, arguments: [flag])
        let first = stdout.components(separatedBy: .newlines).first ?? stdout
        if let r = first.range(of: #"(\d+\.\d+[\.\d]*)"#, options: .regularExpression) {
            return String(first[r])
        }
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - State

    private func buildInitialState() {
        let m = loadManifest()
        func st(_ id: String, _ ver: String?) -> Dependency.Status {
            ver != nil && fileExists(id) ? .installed : .notInstalled
        }
        func pluginInstalled() -> Dependency.Status {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".packer.d/plugins/github.com/cirruslabs/tart")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return files.contains(where: { $0.hasPrefix("packer-plugin-tart") }) ? .installed : .notInstalled
        }
        dependencies = [
            Dependency(id: "tart",               displayName: "tart",
                       currentVersion: m.tart,               latestVersion: nil,
                       binaryPath: depsDirectory.appendingPathComponent("tart.app/Contents/MacOS/tart"),
                       isRequired: true, status: st("tart", m.tart)),
            Dependency(id: "packer",             displayName: "packer",
                       currentVersion: m.packer,             latestVersion: nil,
                       binaryPath: depsDirectory.appendingPathComponent("packer"),
                       isRequired: true, status: st("packer", m.packer)),
            Dependency(id: "mist-cli",           displayName: "mist-cli",
                       currentVersion: m.mistCLI,            latestVersion: nil,
                       binaryPath: depsDirectory.appendingPathComponent("mist-cli"),
                       isRequired: false, status: st("mist-cli", m.mistCLI)),
            Dependency(id: "tart-packer-plugin", displayName: "packer-plugin-tart",
                       currentVersion: m.tartPackerPlugin,   latestVersion: nil,
                       binaryPath: depsDirectory.appendingPathComponent("tart-packer-plugin"),
                       isRequired: true, status: pluginInstalled()),
            Dependency(id: "jq",                 displayName: "jq",
                       currentVersion: m.jq,                 latestVersion: nil,
                       binaryPath: depsDirectory.appendingPathComponent("jq"),
                       isRequired: true, status: st("jq", m.jq)),
        ]
    }

    private func refreshStatuses(checkLatest: Bool = false) async {
        for dep in dependencies where dep.isReady {
            let version = try? await readVersion(binaryPath: dep.binaryPath.path, id: dep.id)
            updateInstalledVersion(id: dep.id, version: version)
        }
    }

    private func updateStatus(id: String, to status: Dependency.Status) {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        let d = dependencies[i]
        dependencies[i] = Dependency(id: d.id, displayName: d.displayName,
                                      currentVersion: d.currentVersion, latestVersion: d.latestVersion,
                                      binaryPath: d.binaryPath, isRequired: d.isRequired, status: status)
    }

    private func updateInstalledVersion(id: String, version: String?) {
        guard let i = dependencies.firstIndex(where: { $0.id == id }) else { return }
        let d = dependencies[i]
        dependencies[i] = Dependency(id: d.id, displayName: d.displayName,
                                      currentVersion: version, latestVersion: d.latestVersion,
                                      binaryPath: d.binaryPath, isRequired: d.isRequired,
                                      status: version != nil ? .installed : d.status)
        saveManifest()
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
            default: break
            }
        }
        if let data = try? JSONEncoder().encode(m) { try? data.write(to: manifestURL) }
    }

    // MARK: - Platform

    private var isAppleSilicon: Bool {
        var info = utsname(); uname(&info)
        return withUnsafeBytes(of: &info.machine) {
            $0.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) } ?? ""
        } == "arm64"
    }
}
