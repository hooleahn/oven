import SwiftUI

struct BrowseGHCRSheet: View {
    let token: String?
    let trackedRefs: Set<String>
    let activeDownloads: [String: Double]
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ownerInput = ""
    @State private var packages: [GHCRPackageInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastSearchedOwner = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse GHCR Images").font(.headline)
                    Text("Search a GitHub org or user's container packages")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16).background(.bar)
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("", text: $ownerInput,
                          prompt: Text("GitHub org or username (e.g. cirruslabs)").foregroundColor(.secondary))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Search") { Task { await search() } }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(ownerInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow).font(.caption)
                Text("Only macOS images built for Tart will work. Other container images can be added but will fail to run.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.08))
            Divider()

            if packages.isEmpty && lastSearchedOwner.isEmpty {
                EmptyStateView(
                    "Browse GHCR",
                    systemImage: "externaldrive.connected.to.line.below",
                    description: "Enter a GitHub org or username to browse their container packages."
                )
            } else if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching packages for \"\(lastSearchedOwner)\"…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                EmptyStateView(
                    "Fetch Failed",
                    systemImage: "exclamationmark.triangle",
                    description: err
                )
            } else if packages.isEmpty {
                EmptyStateView(
                    "No Packages Found",
                    systemImage: "shippingbox",
                    description: "No container packages found for \"\(lastSearchedOwner)\". Check the name, or add a GitHub PAT for ghcr.io in Integrations to access private packages."
                )
            } else {
                List(packages) { pkg in
                    GHCRPackageRow(
                        pkg: pkg,
                        trackedRefs: trackedRefs,
                        activeDownloads: activeDownloads
                    ) { imageRef in
                        onAdd(imageRef)
                        dismiss()
                    }
                }
                .listStyle(.inset)
            }

            if token == nil {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary).font(.caption)
                    Text("Add a GitHub PAT for ghcr.io in Integrations to browse private packages.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    SettingsLink {
                        Text("Integrations").font(.caption).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
            }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 480)
    }

    private func search() async {
        let owner = ownerInput.trimmingCharacters(in: .whitespaces)
        guard !owner.isEmpty else { return }
        lastSearchedOwner = owner
        isLoading = true
        errorMessage = nil
        do {
            packages = try await RegistryService.fetchGHCRPackages(owner: owner, token: token)
        } catch {
            errorMessage = error.localizedDescription
            packages = []
        }
        isLoading = false
    }
}

// MARK: - Package row

struct GHCRPackageRow: View {
    let pkg: GHCRPackageInfo
    let trackedRefs: Set<String>
    let activeDownloads: [String: Double]
    let onAdd: (String) -> Void

    @State private var selectedTag: String

    init(pkg: GHCRPackageInfo, trackedRefs: Set<String>, activeDownloads: [String: Double],
         onAdd: @escaping (String) -> Void) {
        self.pkg = pkg
        self.trackedRefs = trackedRefs
        self.activeDownloads = activeDownloads
        self.onAdd = onAdd
        _selectedTag = State(initialValue: pkg.defaultTag)
    }

    private var selectedRef: String { pkg.ref(tag: selectedTag) }
    private var isTracked: Bool { trackedRefs.contains(selectedRef) }
    private var downloadProgress: Double? { activeDownloads[selectedRef] }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3).foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pkg.name).fontWeight(.medium)
                    if pkg.tags.count > 1 {
                        Text("·").foregroundStyle(.tertiary)
                        Picker("", selection: $selectedTag) {
                            ForEach(pkg.tags, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.system(.caption, design: .monospaced))
                    }
                }
                if let desc = pkg.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(selectedRef)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let progress = downloadProgress {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 80)
                    Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            } else if isTracked {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button("Add") { onAdd(selectedRef) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
