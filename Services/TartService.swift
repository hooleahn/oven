import Foundation

// MARK: - Tart list output shape

struct TartVMInfo: Decodable {
    let name: String
    let state: String
    let size: Int?
    let source: String?

    // tart list --format json uses Title-Case keys: "Name", "State", "Source", "Size"
    enum CodingKeys: String, CodingKey {
        case name   = "Name"
        case state  = "State"
        case size   = "Size"
        case source = "Source"
    }
}

// MARK: - TartService

actor TartService {

    private let runner: ProcessRunner
    /// Managed or initial binary path. If AppSettings is in custom mode and a
    /// non-empty tart path is configured, `resolvedTartPath` returns that instead.
    private let tartPath: String
    private let registryUsername: String?
    private let registryPassword: String?

    /// Returns the effective tart binary path, checking AppSettings at call time
    /// so that mid-session custom-path changes are immediately reflected.
    private var resolvedTartPath: String {
        AppSettings.load().effectivePath(for: "tart") ?? tartPath
    }

    init(runner: ProcessRunner, tartPath: String,
         registryUsername: String? = nil, registryPassword: String? = nil) {
        self.runner = runner
        self.tartPath = tartPath
        self.registryUsername = registryUsername
        self.registryPassword = registryPassword
    }

    /// Environment passed to every tart subprocess.
    /// Includes TART_HOME and optional registry credentials.
    private var tartEnv: [String: String] {
        var env: [String: String] = [:]
        let home = AppSettings.load().resolvedTartHome.path
        env["TART_HOME"] = home
        if let h = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = h }
        // Registry credentials — tart reads these automatically, no login step needed
        if let u = registryUsername { env["TART_REGISTRY_USERNAME"] = u }
        if let p = registryPassword { env["TART_REGISTRY_PASSWORD"] = p }
        return env
    }

    /// tartEnv with TART_NO_AUTO_PRUNE set, which disables automatic pruning for that invocation.
    private var noPruneEnv: [String: String] {
        var env = tartEnv
        env["TART_NO_AUTO_PRUNE"] = ""
        return env
    }

    private var pruneOnPull: Bool {
        UserDefaults.standard.object(forKey: "prune.onPull") as? Bool ?? true
    }
    private var pruneOnClone: Bool {
        UserDefaults.standard.object(forKey: "prune.onClone") as? Bool ?? true
    }
    private var pruneCloneLimitGB: Int {
        UserDefaults.standard.object(forKey: "prune.cloneLimitGB") as? Int ?? 100
    }

    // MARK: - List

    /// List all VMs (default — both local and OCI).
    func list() async throws -> [TartVMInfo] {
        try await listFiltered(source: nil)
    }

    /// List only locally-built VMs.
    func listLocal() async throws -> [TartVMInfo] {
        try await listFiltered(source: "local")
    }

    /// List only OCI-sourced VMs (pulled from a registry).
    func listOCI() async throws -> [TartVMInfo] {
        try await listFiltered(source: "oci")
    }

    private func listFiltered(source: String?) async throws -> [TartVMInfo] {
        do {
            var args = ["list", "--format", "json"]
            if let src = source { args += ["--source", src] }
            let (stdout, _) = try await runner.run(resolvedTartPath, arguments: args, environment: tartEnv)
            let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([TartVMInfo].self, from: data)
            } catch {
                await AppLogger.shared.error("tart list decode failed: \(error) — raw: \(trimmed.prefix(200))", source: "TartService")
                return []
            }
        } catch ProcessError.nonZeroExit(let code, _) where code == 9 {
            return []
        }
    }

    // MARK: - Run / Stop / Suspend

    /// Start a VM. Returns an AsyncStream of output events for live log display.
    enum RunMode { case native, vnc, headless, recovery }

    func run(name: String, mode: RunMode = .native,
             sharedFolders: [VirtualMachine.SharedFolder] = []) async -> AsyncStream<ProcessEvent> {
        var args = ["run", name]
        switch mode {
        case .native:   break
        case .vnc:      args.append("--vnc")
        case .headless: args.append("--no-graphics")
        case .recovery: args.append("--recovery")
        }
        for folder in sharedFolders {
            args += ["--dir", folder.tartArg]
        }
        return await runner.stream(resolvedTartPath, arguments: args, environment: tartEnv)
    }

    func stop(name: String, timeout: Int = 30) async throws {
        // Try graceful stop with timeout first, fall back to immediate stop
        do {
            try await runner.run(resolvedTartPath,
                arguments: ["stop", "--timeout", "\(timeout)", name],
                environment: tartEnv)
        } catch {
            try await runner.run(resolvedTartPath, arguments: ["stop", name], environment: tartEnv)
        }
    }

    func suspend(name: String) async throws {
        try await runner.run(resolvedTartPath, arguments: ["suspend", name], environment: tartEnv)
    }

    // MARK: - Clone / Delete

    func clone(source: String, destination: String) async throws {
        var args = ["clone", source, destination]
        let env: [String: String]
        if pruneOnClone {
            args += ["--prune-limit", "\(pruneCloneLimitGB)"]
            env = tartEnv
        } else {
            env = noPruneEnv
        }
        try await runner.run(resolvedTartPath, arguments: args, environment: env)
    }

    func delete(name: String) async throws {
        try await runner.run(resolvedTartPath, arguments: ["delete", name], environment: tartEnv)
    }

    func rename(name: String, to newName: String) async throws {
        try await runner.run(resolvedTartPath, arguments: ["rename", name, newName], environment: tartEnv)
    }

    // MARK: - IP address

    func ip(name: String, waitSeconds: Int = 60) async throws -> String {
        let (stdout, _) = try await runner.run(
            resolvedTartPath,
            arguments: ["ip", name, "--wait", "\(waitSeconds)"],
            environment: tartEnv
        )
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Set (reconfigure hardware)

    func set(name: String, cpu: Int? = nil, memoryGB: Int? = nil, diskGB: Int? = nil,
             display: String? = nil,   // e.g. "1920x1080"
             randomSerial: Bool = false, randomMAC: Bool = false,
             displayRefit: Bool = false) async throws {
        var args = ["set", name]
        if let cpu      { args += ["--cpu", "\(cpu)"] }
        if let memoryGB { args += ["--memory", "\(memoryGB * 1024)"] }
        if let diskGB   { args += ["--disk-size", "\(diskGB)"] }
        if let display  { args += ["--display", display] }
        if displayRefit  { args.append("--display-refit") }
        if randomSerial  { args.append("--random-serial") }
        if randomMAC     { args.append("--random-mac") }
        try await runner.run(resolvedTartPath, arguments: args, environment: tartEnv)
    }

    // MARK: - Get (live VM config from tart)

    struct TartVMConfig: Decodable {
        let cpu: Int?
        let memory: Int?      // MB
        let disk: Int?        // GB
        let display: String?
        enum CodingKeys: String, CodingKey {
            case cpu = "CPU"
            case memory = "Memory"
            case disk = "Disk"
            case display = "Display"
        }
    }

    func get(name: String) async throws -> TartVMConfig {
        let (stdout, _) = try await runner.run(
            resolvedTartPath, arguments: ["get", name, "--format", "json"], environment: tartEnv)
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw NSError(domain: "TartService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty tart get output"])
        }
        return try JSONDecoder().decode(TartVMConfig.self, from: data)
    }

    // MARK: - Create from IPSW

    /// Create a new VM from a local IPSW file. Streams progress output.
    func create(name: String, fromIPSW ipswPath: String, diskGB: Int) async -> AsyncStream<ProcessEvent> {
        let args = ["create", name, "--from-ipsw", ipswPath, "--disk-size", "\(diskGB)"]
        return await runner.stream(resolvedTartPath, arguments: args, environment: tartEnv)
    }

    // MARK: - Pull / Push (registry)

    /// Pull an OCI image into tart's cache (no local name — appears as OCI source in tart list).
    /// Use this for Base VM images from a registry.
    func pullToCache(imageRef: String) async -> AsyncStream<ProcessEvent> {
        let env = pruneOnPull ? tartEnv : noPruneEnv
        return await runner.stream(resolvedTartPath, arguments: ["pull", imageRef], environment: env)
    }

    /// Clone a remote OCI image to a named local VM (appears as local in tart list).
    /// Use this for regular VMs cloned from a registry image.
    func clone(imageRef: String, to localName: String) async -> AsyncStream<ProcessEvent> {
        var args = ["clone", imageRef, localName]
        let env: [String: String]
        if pruneOnClone {
            args += ["--prune-limit", "\(pruneCloneLimitGB)"]
            env = tartEnv
        } else {
            env = noPruneEnv
        }
        return await runner.stream(resolvedTartPath, arguments: args, environment: env)
    }

    /// Push a local VM to a registry. Streams progress.
    func push(name: String, to imageRef: String) async -> AsyncStream<ProcessEvent> {
        await runner.stream(resolvedTartPath, arguments: ["push", name, imageRef], environment: tartEnv)
    }

    // MARK: - Login

    func login(registry: String, username: String, password: String) async throws {
        var env = tartEnv
        env["TART_REGISTRY_USERNAME"] = username
        env["TART_REGISTRY_PASSWORD"] = password
        try await runner.run(
            resolvedTartPath,
            // Pass --username explicitly; tart reads password from TART_REGISTRY_PASSWORD env
            arguments: ["login", "--username", username, registry],
            environment: env
        )
    }
}
