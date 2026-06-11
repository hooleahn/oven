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
        let first = imageRef.components(separatedBy: "/").first ?? ""
        return (first.contains(".") || first.contains(":") || first == "localhost") ? first : registry
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
    let tags: [String]      // available version tags; "latest" first when present

    var defaultTag: String { tags.contains("latest") ? "latest" : (tags.first ?? "latest") }

    func ref(tag: String) -> String {
        let base = imageRef.components(separatedBy: ":").first ?? imageRef
        return "\(base):\(tag)"
    }

    var registryImage: RegistryImage {
        RegistryImage(id: UUID(), registry: "ghcr.io", imageRef: imageRef, isPulled: false)
    }

    init(id: String, imageRef: String, os: String, variant: String, description: String, tags: [String] = ["latest"]) {
        self.id = id; self.imageRef = imageRef; self.os = os
        self.variant = variant; self.description = description; self.tags = tags
    }
}

// MARK: - GitHub Container Registry browsing

enum GHCRFetchError: LocalizedError {
    case authRequired

    var errorDescription: String? {
        "Authentication required. Add a GitHub PAT with read:packages scope for ghcr.io in Integrations."
    }
}

struct GHCRPackageInfo: Identifiable, Sendable {
    let id: String       // e.g. "cirruslabs/macos-sequoia-base"
    let name: String
    let owner: String
    let description: String?
    let tags: [String]   // "latest" first, then version tags descending

    var defaultTag: String { tags.contains("latest") ? "latest" : (tags.first ?? "latest") }
    var defaultRef: String { "ghcr.io/\(owner)/\(name):\(defaultTag)" }
    func ref(tag: String) -> String { "ghcr.io/\(owner)/\(name):\(tag)" }
}

extension RegistryService {

    // MARK: Version tag fetching

    /// Fetches up to 10 recent version tags for a single GHCR package.
    /// Returns ["latest"] on any failure so callers always get a usable default.
    private static func fetchVersionTags(owner: String, scope: String, package: String,
                                         headers: [String: String]) async -> [String] {
        let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? package
        guard let url = URL(string: "https://api.github.com/\(scope)/\(owner)/packages/container/\(encoded)/versions?per_page=10") else {
            return ["latest"]
        }
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        struct Version: Decodable {
            struct Metadata: Decodable {
                struct Container: Decodable { let tags: [String] }
                let container: Container
            }
            let metadata: Metadata
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let versions = try? JSONDecoder().decode([Version].self, from: data)
        else { return ["latest"] }

        var allTags = versions.flatMap { $0.metadata.container.tags }.filter { !$0.isEmpty }
        let hasLatest = allTags.contains("latest")
        allTags = allTags.filter { $0 != "latest" }.sorted(by: >)
        if hasLatest { allTags.insert("latest", at: 0) }
        return allTags.isEmpty ? ["latest"] : allTags
    }

    // MARK: Browse any GHCR org / user

    /// Lists all container packages for a GitHub org or user, including version tags.
    /// Tries /orgs/ first, falls back to /users/ on 404.
    /// Throws GHCRFetchError.authRequired on 401/403.
    static func fetchGHCRPackages(owner: String, token: String?) async throws -> [GHCRPackageInfo] {
        var headers: [String: String] = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        ]
        if let token { headers["Authorization"] = "Bearer \(token)" }

        struct Package: Decodable {
            let name: String
            let description: String?
        }

        var packages: [Package] = []
        var resolvedScope = ""

        for scope in ["orgs", "users"] {
            guard let url = URL(string: "https://api.github.com/\(scope)/\(owner)/packages?package_type=container&per_page=100") else { continue }
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { continue }

            switch http.statusCode {
            case 200:
                packages = (try? JSONDecoder().decode([Package].self, from: data)) ?? []
                resolvedScope = scope
            case 401, 403:
                throw GHCRFetchError.authRequired
            default:
                break
            }
            if !resolvedScope.isEmpty { break }
        }

        guard !packages.isEmpty, !resolvedScope.isEmpty else { return [] }

        // Fetch version tags for all packages in parallel
        return try await withThrowingTaskGroup(of: GHCRPackageInfo.self) { group in
            for pkg in packages {
                let name = pkg.name; let desc = pkg.description
                group.addTask {
                    let tags = await fetchVersionTags(owner: owner, scope: resolvedScope, package: name, headers: headers)
                    return GHCRPackageInfo(id: "\(owner)/\(name)", name: name, owner: owner, description: desc, tags: tags)
                }
            }
            var result: [GHCRPackageInfo] = []
            for try await info in group { result.append(info) }
            return result.sorted { $0.name < $1.name }
        }
    }

    // MARK: Dynamic Cirrus Labs catalogue

    /// Fetches the live Cirrus Labs macOS catalogue including per-package version tags.
    /// Requires a GitHub PAT with `read:packages` scope.
    /// Falls back to `cirrusLabsCatalogue` if the package list fetch fails.
    static func fetchCirrusCatalogue(token: String) async throws -> [CirrusLabsImage] {
        guard let url = URL(string: "https://api.github.com/orgs/cirruslabs/packages?package_type=container&per_page=100") else {
            return cirrusLabsCatalogue
        }
        let headers: [String: String] = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Authorization": "Bearer \(token)"
        ]
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        struct Package: Decodable {
            let name: String
            let description: String?
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return cirrusLabsCatalogue
        }
        let packages = try JSONDecoder().decode([Package].self, from: data)

        // Build CirrusLabsImage entries in parallel, fetching version tags for each
        let fetched: [CirrusLabsImage] = try await withThrowingTaskGroup(of: CirrusLabsImage?.self) { group in
            for pkg in packages.filter({ $0.name.hasPrefix("macos-") }) {
                let name = pkg.name; let pkgDesc = pkg.description
                group.addTask {
                    let parts = name.dropFirst("macos-".count).components(separatedBy: "-")
                    guard parts.count >= 2 else { return nil }

                    let os: String
                    switch parts[0] {
                    case "golden-gate": os = "macOS 27 Golden Gate"
                    case "tahoe":    os = "macOS 26 Tahoe"
                    case "sequoia":  os = "macOS 15 Sequoia"
                    case "sonoma":   os = "macOS 14 Sonoma"
                    case "ventura":  os = "macOS 13 Ventura"
                    case "monterey": os = "macOS 12 Monterey"
                    default:         os = "macOS \(parts[0].capitalized)"
                    }

                    let variantSlug = parts[1...].joined(separator: "-")
                    let variant: String; let desc: String
                    switch variantSlug {
                    case "vanilla": (variant, desc) = ("Vanilla", "Clean macOS install, no extras.")
                    case "base":    (variant, desc) = ("Base",    "Includes Homebrew, Git, common build tools.")
                    case "xcode":   (variant, desc) = ("Xcode",   "Base + latest Xcode release.")
                    default:        (variant, desc) = (variantSlug.capitalized, pkgDesc ?? "\(name) image from Cirrus Labs.")
                    }

                    let tags = await fetchVersionTags(owner: "cirruslabs", scope: "orgs", package: name, headers: headers)
                    let ref = "ghcr.io/cirruslabs/\(name):latest"
                    return CirrusLabsImage(id: ref, imageRef: ref, os: os, variant: variant, description: desc, tags: tags)
                }
            }
            var result: [CirrusLabsImage] = []
            for try await img in group { if let img { result.append(img) } }
            return result
        }

        // Merge: fetched is authoritative; keep any static entries not found remotely
        var result = fetched
        let fetchedRefs = Set(fetched.map { $0.imageRef })
        for img in cirrusLabsCatalogue where !fetchedRefs.contains(img.imageRef) {
            result.append(img)
        }

        let osOrder = ["macOS 27 Golden Gate", "macOS 26 Tahoe", "macOS 15 Sequoia", "macOS 14 Sonoma",
                       "macOS 13 Ventura", "macOS 12 Monterey"]
        result.sort {
            let i0 = osOrder.firstIndex(of: $0.os) ?? osOrder.count
            let i1 = osOrder.firstIndex(of: $1.os) ?? osOrder.count
            return i0 != i1 ? i0 < i1 : $0.variant < $1.variant
        }
        return result
    }

    // MARK: Static fallback catalogue

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
