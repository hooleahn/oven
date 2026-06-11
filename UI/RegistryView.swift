import SwiftUI

struct RegistryView: View {
    @Environment(VMStore.self) private var vmStore
    @Environment(BaseVMStore.self) private var baseVMStore
    @Environment(AppState.self) private var appState
    @State private var rvm = RegistryViewModel()
    @State private var searchText: String = ""
    @State private var lastRefreshedAt: Date? = nil
    @State private var isRefreshing: Bool = false
    @State private var refreshRotation: Double = 0
    @State private var showBrowseGHCR = false
    @State private var pullTasks: [String: Task<Void, Never>] = [:]
    @State private var pullLocalNames: [String: String] = [:]
    @FocusState private var newImageRefFocused: Bool

    private func coarseAge(of date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 120     { return "just now" }
        if s < 3600    { return "\(s / 60) min ago" }
        if s < 86_400  { return "\(s / 3600) hr ago" }
        return "\(s / 86_400)d ago"
    }

    /// All known registry hosts — from tracked images, saved credentials,
    /// and the two defaults — sorted with defaults first.
    var registries: [String] {
        var seen = Set<String>()
        var result: [String] = []
        // Always include defaults first
        for r in ["ghcr.io", "docker.io"] {
            if seen.insert(r).inserted { result.append(r) }
        }
        // Add hosts from tracked images
        for img in rvm.images {
            let host = img.registryHost
            if seen.insert(host).inserted { result.append(host) }
        }
        // Add hosts from saved credentials
        for cred in rvm.credentials {
            if seen.insert(cred.registry).inserted { result.append(cred.registry) }
        }
        return result
    }

    private var registryService: RegistryService? {
        let tartPath = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        return rvm.makeRegistryService(tartPath: tartPath)
    }

    private var ghcrToken: String? {
        rvm.credentials.first(where: { $0.registry == "ghcr.io" })?.password
    }

    var filteredImages: [RegistryImage] {
        let base = rvm.images.filter { $0.registryHost == rvm.selectedRegistry }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.imageRef.lowercased().contains(q) ||
            ($0.localName?.lowercased().contains(q) == true)
        }
    }

    var credentialForSelected: RegistryCredential? {
        rvm.credentials.first(where: { $0.registry == rvm.selectedRegistry })
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Middle content area ──────────────────────────────────────────
            VStack(spacing: 0) {
                // Credentials banner — part of layout flow so it doesn't overlap the list
                if credentialForSelected == nil {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.slash.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No credentials for \(rvm.selectedRegistry)")
                                .font(.callout).fontWeight(.medium)
                            Text("Add them in Preferences to push or pull private images.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsLink {
                            Text("Add credentials")
                                .font(.callout)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.orange.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    Divider()
                }

                // "Showing N images on [registry]" context label
                if !filteredImages.isEmpty {
                    HStack {
                        Text("Showing \(filteredImages.count) image\(filteredImages.count == 1 ? "" : "s") on \(rvm.selectedRegistry)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let cred = credentialForSelected {
                            Label(cred.username, systemImage: "person.badge.key.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.bar)
                    Divider()
                }

                if filteredImages.isEmpty {
                    EmptyStateView(
                        "No Images",
                        systemImage: "externaldrive.connected.to.line.below",
                        description: "Add an image reference in the bar below to pull or push images on \(rvm.selectedRegistry)."
                    )
                } else {
                    List(filteredImages) { image in
                        RegistryImageRow(
                            image: image,
                            downloadProgress: appState.registryDownloads[image.imageRef],
                            onPull: { rvm.pendingPull = image },
                            onCancelPull: {
                                pullTasks[image.imageRef]?.cancel()
                                pullTasks.removeValue(forKey: image.imageRef)
                                appState.registryDownloads.removeValue(forKey: image.imageRef)
                                let localName = pullLocalNames.removeValue(forKey: image.imageRef)
                                Task { await cleanupCancelledPull(imageRef: image.imageRef, localName: localName) }
                            },
                            onCreateVM: { Task { await createVMFromImage(image) } },
                            onDelete: { Task { await deleteImage(image) } }
                        )
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Bottom bar — always visible, always at bottom ────────────────
            Divider()
            addImageBar
        }
        .background(
            Button("") { newImageRefFocused = true }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        )
        .navigationTitle("Image Registry")
        .alert("Error", isPresented: Binding(
            get: { rvm.errorMessage != nil },
            set: { if !$0 { rvm.errorMessage = nil } }
        )) {
            Button("OK") { rvm.errorMessage = nil }
        } message: {
            Text(rvm.errorMessage ?? "")
        }
        .searchable(text: $searchText, prompt: "Search \(registryShortName(for: rvm.selectedRegistry)) images…")
        .toolbar {
            // 1. Principal — segmented registry picker centred in the toolbar
            ToolbarItem(placement: .principal) {
                Picker("", selection: $rvm.selectedRegistry) {
                    ForEach(registries, id: \.self) { registry in
                        Text(registryShortName(for: registry)).tag(registry)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .onChange(of: registries) { _, newRegs in
                    if !newRegs.contains(rvm.selectedRegistry) {
                        rvm.selectedRegistry = newRegs.first ?? "ghcr.io"
                    }
                }
            }

            // 2. Primary action — Browse Cirrus Labs catalogue (⌘B)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    rvm.showCirrusCatalogue = true
                } label: {
                    Label("Cirrus Labs", systemImage: "building.columns")
                }
                .keyboardShortcut("b", modifiers: .command)
                .help("Browse Cirrus Labs public macOS images (⌘B)")
            }

            // 3. Primary action — Browse any GHCR org / user
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBrowseGHCR = true
                } label: {
                    Label("Browse GHCR", systemImage: "rectangle.stack.badge.person.crop")
                }
                .help("Browse a GitHub org or user's container packages")
            }

            // Last-synced label
            ToolbarItem(placement: .automatic) {
                if let refreshed = lastRefreshedAt {
                    Text("Synced " + coarseAge(of: refreshed))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8)
                }
            }

            // Refresh (⌘R)
            ToolbarItem(placement: .automatic) {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        refreshRotation = 360
                    }
                    let tartPath = AppSettings.defaultLocalStorageRoot
                        .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
                    Task {
                        await rvm.syncFromTart(tartPath: tartPath)
                        lastRefreshedAt = Date()
                        isRefreshing = false
                        refreshRotation = 0
                    }
                } label: {
                    Label("Sync from Tart", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Sync registry images from local tart (⌘R)")
            }
        }
        .task { updateWindowTitle() }
        .onChange(of: rvm.selectedRegistry) { _, _ in updateWindowTitle() }
        .task {
            rvm.load()
            let tartPath = AppSettings.defaultLocalStorageRoot
                .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
            await rvm.syncFromTart(tartPath: tartPath)
            lastRefreshedAt = Date()
        }
        .sheet(isPresented: $rvm.showCirrusCatalogue) {
            CirrusCatalogueSheet(
                trackedRefs: Set(rvm.images.map { $0.imageRef }),
                activeDownloads: appState.registryDownloads,
                token: ghcrToken
            ) { imageRef in
                guard !rvm.images.contains(where: { $0.imageRef == imageRef }) else { return }
                let host = registryHostFrom(imageRef, fallback: rvm.selectedRegistry)
                let img = RegistryImage(id: UUID(), registry: host, imageRef: imageRef, isPulled: false)
                rvm.images.append(img)
                rvm.saveImages()
                rvm.pendingPull = img
            }
        }
        .sheet(isPresented: $showBrowseGHCR) {
            BrowseGHCRSheet(
                token: ghcrToken,
                trackedRefs: Set(rvm.images.map { $0.imageRef }),
                activeDownloads: appState.registryDownloads
            ) { imageRef in
                guard !rvm.images.contains(where: { $0.imageRef == imageRef }) else { return }
                let host = registryHostFrom(imageRef, fallback: rvm.selectedRegistry)
                let img = RegistryImage(id: UUID(), registry: host, imageRef: imageRef, isPulled: false)
                rvm.images.append(img)
                rvm.saveImages()
                rvm.pendingPull = img
            }
        }
        .sheet(item: $rvm.pendingPull) { image in
            PullDestinationSheet(image: image) { asBase, username, password in
                rvm.pendingPull = nil
                rvm.pendingPullIsBase = asBase
                rvm.pendingPullUsername = username
                rvm.pendingPullPassword = password
                let rawLocal = image.imageRef
                    .components(separatedBy: "/").last?
                    .replacingOccurrences(of: ":", with: "-") ?? "pulled-vm"
                pullLocalNames[image.imageRef] = asBase ? image.imageRef : rawLocal
                let task = Task { await pullImage(image, asBaseVM: asBase) }
                pullTasks[image.imageRef] = task
            }
            .environment(vmStore)
        }
    }

    // MARK: Window title

    private func updateWindowTitle() {
        appState.windowTitle = "Registry — \(rvm.selectedRegistry)"
        appState.windowSubtitle = ""
    }

    // MARK: Registry icon + short name helpers

    private func registryIcon(for registry: String) -> String {
        switch registry {
        case "ghcr.io":    return "cat.fill"
        case "docker.io":  return "shippingbox.fill"
        default:           return "server.rack"
        }
    }

    private func registryShortName(for registry: String) -> String {
        switch registry {
        case "ghcr.io":   return "GitHub"
        case "docker.io": return "Docker"
        default:
            // Strip common TLDs for brevity: "registry.example.com" → "example"
            let parts = registry.components(separatedBy: ".")
            return parts.count >= 2 ? parts[parts.count - 2].capitalized : registry
        }
    }

    // MARK: Cirrus Labs catalogue

    private var cirrusCatalogueSection: some View {
        VStack(spacing: 0) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { rvm.showCirrusCatalogue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "building.columns")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Cirrus Labs Public Images")
                        .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: rvm.showCirrusCatalogue ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if rvm.showCirrusCatalogue {
                let grouped = Dictionary(grouping: RegistryService.cirrusLabsCatalogue, by: \.os)
                let osOrder = ["macOS 27 Golden Gate", "macOS 26 Tahoe", "macOS 15 Sequoia", "macOS 14 Sonoma",
                               "macOS 13 Ventura", "macOS 12 Monterey"]
                ForEach(osOrder, id: \.self) { os in
                    if let imgs = grouped[os] {
                        HStack(spacing: 0) {
                            Text(os)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .padding(.horizontal, 14).padding(.vertical, 4)
                            Spacer()
                        }
                        .background(.bar)
                        ForEach(imgs) { img in
                            CirrusLabsCatalogueRow(
                                image: img,
                                trackedRefs: Set(rvm.images.map { $0.imageRef }),
                                activeDownloads: appState.registryDownloads
                            ) { imageRef in
                                guard !rvm.images.contains(where: { $0.imageRef == imageRef }) else { return }
                                let host = registryHostFrom(imageRef, fallback: rvm.selectedRegistry)
                                let regImg = RegistryImage(id: UUID(), registry: host, imageRef: imageRef, isPulled: false)
                                rvm.images.append(regImg)
                                rvm.saveImages()
                                rvm.pendingPull = regImg
                            }
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }


    // MARK: Add image bar

    private var addImageBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.plus").foregroundStyle(.secondary)
            TextField("", text: $rvm.newImageRef,
                      prompt: Text("ghcr.io/org/image:tag").foregroundStyle(.secondary))
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .focused($newImageRefFocused)
            Button("Add") {
                let ref = rvm.newImageRef.trimmingCharacters(in: .whitespaces)
                guard !ref.isEmpty else { return }
                // Deduplicate — don't add if this imageRef is already tracked
                guard !rvm.images.contains(where: { $0.imageRef == ref }) else {
                    rvm.errorMessage = "\(ref) is already in your image list."
                    rvm.newImageRef = ""
                    return
                }
                let host = registryHostFrom(ref, fallback: rvm.selectedRegistry)
                let img = RegistryImage(
                    id: UUID(),
                    registry: host,
                    imageRef: ref,
                    isPulled: false
                )
                rvm.images.append(img)
                rvm.saveImages()
                rvm.newImageRef = ""
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .keyboardShortcut(.defaultAction)
            .disabled(rvm.newImageRef.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
    }

    // MARK: Actions

    @MainActor private func pullImage(_ image: RegistryImage, asBaseVM: Bool = false) async {
        guard let svc = registryService else { return }
        let rawLocal = image.imageRef
            .components(separatedBy: "/").last?
            .replacingOccurrences(of: ":", with: "-") ?? "pulled-vm"
        let localName = asBaseVM ? image.imageRef : rawLocal

        appState.registryDownloads[image.imageRef] = 0.0
        defer {
            appState.registryDownloads.removeValue(forKey: image.imageRef)
            pullTasks.removeValue(forKey: image.imageRef)
            pullLocalNames.removeValue(forKey: image.imageRef)
        }

        let stream = await svc.pull(imageRef: image.imageRef, localName: localName,
                                    asBase: asBaseVM, credentials: rvm.credentials)

        let pullResult = await StreamConsumer.consume(stream, onStdout: { line in
            if line.contains("%") {
                let digits = line.filter { $0.isNumber || $0 == "." }
                if let pct = Double(digits) {
                    appState.registryDownloads[image.imageRef] = min(pct / 100.0, 1.0)
                }
            }
        })
        appState.registryDownloads.removeValue(forKey: image.imageRef)

        // Task was cancelled by the user — don't update state
        guard !Task.isCancelled else { return }

        if pullResult.succeeded {
            if let idx = rvm.images.firstIndex(where: { $0.id == image.id }) {
                rvm.images[idx].isPulled  = true
                rvm.images[idx].localName = localName
                rvm.images[idx].pulledAt  = Date()
            }
            rvm.saveImages()
            await vmStore.sync()
            if let idx = rvm.images.firstIndex(where: { $0.id == image.id }) {
                await routePulledImage(rvm.images[idx], asBaseVM: asBaseVM)
            }
        } else {
            let raw = pullResult.combinedOutput
            AppLogger.shared.error("Pull failed (exit \(pullResult.exitCode)): \(raw)", source: "RegistryView")
            rvm.errorMessage = parseTartError(raw) ?? "Pull failed for \(image.imageRef)"
        }
    }

    /// Route a pulled image to either BaseVMStore (as a base VM) or VMStore (as a regular VM)
    @MainActor private func routePulledImage(_ image: RegistryImage, asBaseVM: Bool) async {
        guard let localName = image.localName else { return }
        let username = rvm.pendingPullUsername
        let password = rvm.pendingPullPassword
        if asBaseVM {
            let macOS = rvm.inferOSFromRef(image.imageRef)
            var namedBaseVM = VirtualMachine(name: localName)
            namedBaseVM.isBaseVM = true
            namedBaseVM.registryImageRef = image.imageRef
            namedBaseVM.osName      = macOS.0
            namedBaseVM.macOSVersion = "macOS \(macOS.0.rawValue) \(macOS.1)"
            namedBaseVM.sshUsername  = username.isEmpty ? "admin" : username
            namedBaseVM.cpuCount     = 4
            namedBaseVM.memoryGB     = 8
            namedBaseVM.diskGB       = 80
            namedBaseVM.buildStatus  = VirtualMachine.BuildStatus.ready
            namedBaseVM.vmSource     = VirtualMachine.VMSource.registry
            namedBaseVM.builtAt      = Date()
            if !password.isEmpty { namedBaseVM.sshPassword = password }
            baseVMStore.add(namedBaseVM)
            AppLogger.shared.success(
                "Registered '\(localName)' as Base VM", source: "RegistryView")
        } else {
            await createVMFromImage(image, username: username, password: password)
        }
        rvm.pendingPullUsername = ""
        rvm.pendingPullPassword = ""
    }

    @MainActor private func createVMFromImage(_ image: RegistryImage, username: String = "", password: String = "") async {
        guard image.isPulled else {
            await pullImage(image)
            return
        }
        let tartBinary = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        guard FileManager.default.fileExists(atPath: tartBinary) else { return }
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartBinary)

        let tag = image.imageRef.components(separatedBy: ":").last ?? "latest"
        let repoSlug = image.imageRef
            .components(separatedBy: "/").last?
            .components(separatedBy: ":").first ?? "vm"
        let baseName = "\(repoSlug)-\(tag)"

        var newName = baseName
        var counter = 2
        let existingNames = Set(vmStore.vms.map { $0.name })
        while existingNames.contains(newName) {
            newName = "\(baseName)-\(counter)"
            counter += 1
        }

        appState.registryDownloads[image.imageRef] = 0.0
        defer { appState.registryDownloads.removeValue(forKey: image.imageRef) }

        let cloneStream = await tartSvc.clone(imageRef: image.imageRef, to: newName)
        let cloneResult = await StreamConsumer.logged(cloneStream, source: "RegistryView")
        appState.registryDownloads.removeValue(forKey: image.imageRef)
        if cloneResult.succeeded {
            vmStore.recordRegistryClone(sourceImageRef: image.imageRef)
            await vmStore.sync()
        } else {
            let raw = cloneResult.combinedOutput
            rvm.errorMessage = parseTartError(raw) ?? "Clone failed (exit \(cloneResult.exitCode))"
            AppLogger.shared.error("Clone failed: \(raw)", source: "RegistryView")
        }
    }

    // MARK: Cancel cleanup

    /// Delete any partial tart data left behind by a cancelled pull.
    /// - For non-base pulls (tart clone): deletes the local VM by localName.
    /// - For base pulls (tart pull to OCI cache): deletes by imageRef.
    /// tart delete is a no-op if the VM doesn't exist, so it's safe to call unconditionally.
    @MainActor private func cleanupCancelledPull(imageRef: String, localName: String?) async {
        let tartBinary = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        guard FileManager.default.fileExists(atPath: tartBinary) else { return }
        let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartBinary)
        if let localName {
            try? await tartSvc.delete(name: localName)
        }
        // Also try deleting by imageRef in case it was cached as OCI
        if localName != imageRef {
            try? await tartSvc.delete(name: imageRef)
        }
        await vmStore.sync()
    }

    // MARK: Delete

    @MainActor private func deleteImage(_ image: RegistryImage) async {
        let tartBinary = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
        if image.isPulled && FileManager.default.fileExists(atPath: tartBinary) {
            let tartSvc = TartService(runner: ProcessRunner(), tartPath: tartBinary)
            try? await tartSvc.delete(name: image.imageRef)
        }
        rvm.images.removeAll { $0.id == image.id }
        rvm.saveImages()
        if image.isPulled { await vmStore.sync() }
    }

    // MARK: Persistence




    /// Parse tart's structured error format into a human-readable string.



}

// MARK: - Image row


// MARK: - Pull Destination Sheet


// MARK: - Cirrus Labs catalogue row


// MARK: - Cirrus Labs catalogue sheet


// MARK: - Registry host helpers

/// Extract the registry hostname from an OCI imageRef.
/// Only treats the first path component as a hostname if it looks like one
/// (contains `.` or `:`, or is "localhost"). Otherwise returns `fallback`.
func registryHostFrom(_ imageRef: String, fallback: String) -> String {
    let first = imageRef.components(separatedBy: "/").first ?? ""
    return (first.contains(".") || first.contains(":") || first == "localhost") ? first : fallback
}

// MARK: - Tart error parsing (shared)

func parseTartError(_ raw: String) -> String? {
    let errorLine = raw.components(separatedBy: .newlines)
        .first(where: { $0.hasPrefix("Error:") }) ?? raw

    // Helper: extract HTTP code if present
    func httpCode() -> String? {
        guard let r = errorLine.range(of: "code: ") else { return nil }
        let digits = errorLine[r.upperBound...].prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : String(digits)
    }

    // Pattern 1: message inside details JSON (possibly double-escaped)
    let msgPatterns = [
        #"\\"?message\\"?:\s*\\"?([^"\\]+)\\"?"#,
        #""message"\s*:\s*"([^"\]+)""#,
    ]
    for pattern in msgPatterns {
        if let m = errorLine.range(of: pattern, options: .regularExpression) {
            let matched = String(errorLine[m])
            let parts = matched.components(separatedBy: ":")
            if parts.count >= 2 {
                let raw = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .init(charactersIn: "\"\\{} "))
                let val = raw.replacingOccurrences(of: "\\\"", with: "")
                              .replacingOccurrences(of: "_", with: " ")
                              .trimmingCharacters(in: .whitespacesAndNewlines as CharacterSet)
                if !val.isEmpty {
                    let pretty = val.prefix(1).uppercased() + val.dropFirst()
                    if let code = httpCode() { return "\(code) — \(pretty)" }
                    return pretty
                }
            }
        }
    }

    // Pattern 2: when: "description", code: NNN
    if let whenR = errorLine.range(of: #"when: "([^"]+)""#, options: .regularExpression) {
        let matched = String(errorLine[whenR])
        if let q1 = matched.firstIndex(of: "\""),
           let q2 = matched[matched.index(after: q1)...].firstIndex(of: "\"") {
            let desc = String(matched[matched.index(after: q1)..<q2]).capitalized
            if let code = httpCode() { return "\(code) — \(desc)" }
            return desc
        }
    }

    // Pattern 3: old-style JSON "message":"value"
    let parts = errorLine.components(separatedBy: "message")
    if parts.count >= 2 {
        for sep in [#"":"#, #"":\#"#, #"": "#] {
            let sub = parts[1].components(separatedBy: sep)
            if sub.count >= 2, let end = sub[1].firstIndex(of: "\"") {
                let val = String(sub[1][..<end])
                    .replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines as CharacterSet)
                if !val.isEmpty {
                    let pretty = val.prefix(1).uppercased() + val.dropFirst()
                    if let code = httpCode() { return "\(code) — \(pretty)" }
                    return pretty
                }
            }
        }
    }

    // Pattern 4: CamelCase exception type name → readable words
    if let paren = errorLine.firstIndex(of: "(") {
        let exc = String(errorLine[errorLine.index(errorLine.startIndex, offsetBy: 7)..<paren])
        var words = ""
        for ch in exc {
            if ch.isUppercase && !words.isEmpty { words += " " }
            words.append(ch)
        }
        if let code = httpCode() { return "\(code) — \(words)" }
        return words
    }
    return nil
}
