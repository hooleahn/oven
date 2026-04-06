import Foundation

// MARK: - Registry image info

struct RegistryImage: Identifiable, Codable {
    let id: UUID
    let registry: String
    let imageRef: String
    var isPulled: Bool
    var localName: String?
    var pulledAt: Date?
    var sizeBytes: Int64?

    var registryHost: String {
        imageRef.components(separatedBy: "/").first ?? registry
    }

    // Explicit memberwise init (custom Codable init suppresses the synthesised one)
    init(id: UUID = UUID(), registry: String, imageRef: String,
         isPulled: Bool = false, localName: String? = nil,
         pulledAt: Date? = nil, sizeBytes: Int64? = nil) {
        self.id        = id
        self.registry  = registry
        self.imageRef  = imageRef
        self.isPulled  = isPulled
        self.localName = localName
        self.pulledAt  = pulledAt
        self.sizeBytes = sizeBytes
    }

    // Custom decode: derive `registry` from `imageRef` if missing from older saved files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        imageRef  = try c.decode(String.self, forKey: .imageRef)
        isPulled  = try c.decodeIfPresent(Bool.self, forKey: .isPulled) ?? false
        localName = try c.decodeIfPresent(String.self, forKey: .localName)
        pulledAt  = try c.decodeIfPresent(Date.self, forKey: .pulledAt)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        // Derive registry from imageRef if the field is absent (legacy files)
        registry  = try c.decodeIfPresent(String.self, forKey: .registry)
            ?? imageRef.components(separatedBy: "/").first
            ?? "ghcr.io"
    }
}

// MARK: - RegistryService

actor RegistryService {

    private let runner: ProcessRunner
    private let tartPath: String

    init(runner: ProcessRunner, tartPath: String) {
        self.runner = runner
        self.tartPath = tartPath
    }

    // MARK: - Auth

    /// Login to a registry using stored credentials.
    /// Looks up the credential for the registry host and calls `tart login`.
    func loginIfCredentialed(registry: String, credentials: [RegistryCredential]) async {
        guard let cred = credentials.first(where: { $0.registry == registry }),
              let password = cred.password else {
            await AppLogger.shared.log("No credentials found for \(registry) — skipping login", source: "RegistryService")
            return
        }
        do {
            try await login(registry: registry, username: cred.username, password: password)
            await AppLogger.shared.success("Logged in to \(registry) as \(cred.username)", source: "RegistryService")
        } catch {
            await AppLogger.shared.warning("Login to \(registry) failed: \(error.localizedDescription)", source: "RegistryService")
        }
    }

    func login(registry: String, username: String, password: String) async throws {
        let tartSvc = TartService(runner: runner, tartPath: tartPath)
        try await tartSvc.login(registry: registry, username: username, password: password)
    }

    // MARK: - Pull

    /// Login then pull. Streams progress events.
    /// Pull an image from a registry.
    /// - `asBase: true`  → `tart pull <imageRef>` (caches OCI layers, no local name)
    /// - `asBase: false` → `tart clone <imageRef> <localName>` (creates a named local VM)
    ///
    /// Credentials are passed via TART_REGISTRY_USERNAME / TART_REGISTRY_PASSWORD env vars.
    /// tart reads these automatically — no `tart login` step needed.
    /// See https://github.com/cirruslabs/tart/issues/596
    func pull(imageRef: String, localName: String, asBase: Bool,
              credentials: [RegistryCredential]) async -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
            Task {
                let host = imageRef.components(separatedBy: "/").first ?? ""
                let cred = credentials.first(where: { $0.registry == host })
                let cmd = asBase ? "pull \(imageRef)" : "clone \(imageRef) → \(localName)"
                await AppLogger.shared.log("Pulling \(cmd)", source: "RegistryService")
                let tartSvc = TartService(runner: runner, tartPath: tartPath,
                                          registryUsername: cred?.username,
                                          registryPassword: cred?.password)
                let stream = asBase
                    ? await tartSvc.pullToCache(imageRef: imageRef)
                    : await tartSvc.clone(imageRef: imageRef, to: localName)
                for await event in stream {
                    continuation.yield(event)
                    if case .exit(let code) = event {
                        if code == 0 {
                            await AppLogger.shared.success("Pull complete: \(imageRef)", source: "RegistryService")
                        } else {
                            await AppLogger.shared.error("Pull failed (exit \(code)): \(imageRef)", source: "RegistryService")
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Push

    /// Login then push. Streams progress events.
    func push(localName: String, to imageRef: String,
              credentials: [RegistryCredential]) async -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
            Task {
                let host = imageRef.components(separatedBy: "/").first ?? ""
                await loginIfCredentialed(registry: host, credentials: credentials)
                await AppLogger.shared.log("Pushing \(localName) → \(imageRef)", source: "RegistryService")
                let stream = await runner.stream(tartPath, arguments: ["push", localName, imageRef])
                for await event in stream {
                    continuation.yield(event)
                    if case .exit(let code) = event {
                        if code == 0 {
                            await AppLogger.shared.success("Push complete: \(imageRef)", source: "RegistryService")
                        } else {
                            await AppLogger.shared.error("Push failed (exit \(code)): \(imageRef)", source: "RegistryService")
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - List remote tags (GHCR)

    func listGHCRTags(owner: String, package: String, token: String?) async throws -> [String] {
        let url = URL(string: "https://api.github.com/users/\(owner)/packages/container/\(package)/versions")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Version: Decodable {
            struct Metadata: Decodable {
                struct Container: Decodable { let tags: [String] }
                let container: Container
            }
            let metadata: Metadata
        }
        return try JSONDecoder().decode([Version].self, from: data)
            .flatMap { $0.metadata.container.tags }.sorted()
    }
}

// MARK: - Cirrus Labs catalogue (public images, no token needed)

struct CirrusLabsImage: Identifiable, Sendable {
    let id: String          // full imageRef e.g. "ghcr.io/cirruslabs/macos-tahoe-base:latest"
    let imageRef: String
    let os: String          // "macOS 26 Tahoe"
    let variant: String     // "Base", "Vanilla", "Xcode"
    let description: String

    var registryImage: RegistryImage {
        RegistryImage(id: UUID(), registry: "ghcr.io", imageRef: imageRef, isPulled: false)
    }
}

extension RegistryService {
    /// All publicly available Cirrus Labs macOS images.
    /// These are static and well-known — no API call needed.
    static let cirrusLabsCatalogue: [CirrusLabsImage] = [
        // macOS 26 Tahoe
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-tahoe-vanilla:latest",
            imageRef: "ghcr.io/cirruslabs/macos-tahoe-vanilla:latest",
            os: "macOS 26 Tahoe", variant: "Vanilla",
            description: "Clean macOS install, no extras."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-tahoe-base:latest",
            imageRef: "ghcr.io/cirruslabs/macos-tahoe-base:latest",
            os: "macOS 26 Tahoe", variant: "Base",
            description: "Includes Homebrew, Git, common build tools."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest",
            imageRef: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest",
            os: "macOS 26 Tahoe", variant: "Xcode",
            description: "Base + latest Xcode release."),
        // macOS 15 Sequoia
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-sequoia-vanilla:latest",
            imageRef: "ghcr.io/cirruslabs/macos-sequoia-vanilla:latest",
            os: "macOS 15 Sequoia", variant: "Vanilla",
            description: "Clean macOS install, no extras."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-sequoia-base:latest",
            imageRef: "ghcr.io/cirruslabs/macos-sequoia-base:latest",
            os: "macOS 15 Sequoia", variant: "Base",
            description: "Includes Homebrew, Git, common build tools."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-sequoia-xcode:latest",
            imageRef: "ghcr.io/cirruslabs/macos-sequoia-xcode:latest",
            os: "macOS 15 Sequoia", variant: "Xcode",
            description: "Base + latest Xcode release."),
        // macOS 14 Sonoma
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-sonoma-vanilla:latest",
            imageRef: "ghcr.io/cirruslabs/macos-sonoma-vanilla:latest",
            os: "macOS 14 Sonoma", variant: "Vanilla",
            description: "Clean macOS install, no extras."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-sonoma-base:latest",
            imageRef: "ghcr.io/cirruslabs/macos-sonoma-base:latest",
            os: "macOS 14 Sonoma", variant: "Base",
            description: "Includes Homebrew, Git, common build tools."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-sonoma-xcode:latest",
            imageRef: "ghcr.io/cirruslabs/macos-sonoma-xcode:latest",
            os: "macOS 14 Sonoma", variant: "Xcode",
            description: "Base + latest Xcode release."),
        // macOS 13 Ventura
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-ventura-vanilla:latest",
            imageRef: "ghcr.io/cirruslabs/macos-ventura-vanilla:latest",
            os: "macOS 13 Ventura", variant: "Vanilla",
            description: "Clean macOS install, no extras."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-ventura-base:latest",
            imageRef: "ghcr.io/cirruslabs/macos-ventura-base:latest",
            os: "macOS 13 Ventura", variant: "Base",
            description: "Includes Homebrew, Git, common build tools."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-ventura-xcode:latest",
            imageRef: "ghcr.io/cirruslabs/macos-ventura-xcode:latest",
            os: "macOS 13 Ventura", variant: "Xcode",
            description: "Base + latest Xcode release."),
        // macOS 12 Monterey
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-monterey-vanilla:latest",
            imageRef: "ghcr.io/cirruslabs/macos-monterey-vanilla:latest",
            os: "macOS 12 Monterey", variant: "Vanilla",
            description: "Clean macOS install, no extras."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-monterey-base:latest",
            imageRef: "ghcr.io/cirruslabs/macos-monterey-base:latest",
            os: "macOS 12 Monterey", variant: "Base",
            description: "Includes Homebrew, Git, common build tools."),
        CirrusLabsImage(id: "ghcr.io/cirruslabs/macos-monterey-xcode:latest",
            imageRef: "ghcr.io/cirruslabs/macos-monterey-xcode:latest",
            os: "macOS 12 Monterey", variant: "Xcode",
            description: "Base + latest Xcode release."),
    ]
}
