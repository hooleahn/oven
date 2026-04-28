import SwiftUI
import AppKit

/// Shown on first launch (or when deps are missing) while DependencyManager bootstraps.
/// Once allReady == true, the app transitions to the main window.
struct SetupView: View {
    @Bindable var depManager: DependencyManager

    @State private var storageRoot: URL = AppSettings.defaultLocalStorageRoot
    @State private var isInstalling = false

    private var canInstallAll: Bool {
        depManager.dependencies.contains { $0.status == .notInstalled || $0.status == .error }
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Oven needs these tools to build VMs")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Text("Components install to \(storageRoot.path).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") {
                        chooseStorageRoot()
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)

            Divider()

            // MARK: Dependency list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(depManager.dependencies) { dep in
                        DependencyRow(dep: dep, depManager: depManager)
                    }
                }
                .padding(.vertical, 8)
            }

            // MARK: Install log
            if !depManager.installLog.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(depManager.installLog.indices, id: \.self) { i in
                                Text(depManager.installLog[i])
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 90)
                    .background(.quaternary)
                    .onChange(of: depManager.installLog.count) { _, count in
                        if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // MARK: Footer
            HStack {
                Button("Skip for now") {
                    // Mark all not-required-for-launch deps as skipped so allReady passes
                    for dep in depManager.dependencies where dep.status == .notInstalled {
                        depManager.skipDependency(id: dep.id)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canInstallAll || depManager.isCheckingVersions)

                Spacer()

                if depManager.isCheckingVersions {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if depManager.allReady {
                    Label("All set", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }

                Button("Install All") {
                    isInstalling = true
                    Task {
                        await depManager.installAll()
                        isInstalling = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstallAll || isInstalling || depManager.isCheckingVersions)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 580, height: 520)
        .onAppear {
            storageRoot = AppSettings.load().depsRoot.deletingLastPathComponent()
        }
    }

    // MARK: - Helpers

    private func chooseStorageRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a folder where Oven will install its tools."
        if panel.runModal() == .OK, let url = panel.url {
            storageRoot = url
            // Persist change via AppSettings
            var settings = AppSettings.load()
            settings = AppSettings(
                vmStorageRoot: settings.vmStorageRoot,
                ipswStorageRoot: settings.ipswStorageRoot,
                packerTemplatesRoot: settings.packerTemplatesRoot,
                depsRoot: url.appendingPathComponent("deps", isDirectory: true),
                tartHome: settings.tartHome,
                ipswDownloadMode: settings.ipswDownloadMode,
                dependencyMode: settings.dependencyMode,
                customPaths: settings.customPaths
            )
            try? settings.save()
        }
    }
}

// MARK: - Dependency row

private struct DependencyRow: View {
    let dep: Dependency
    let depManager: DependencyManager

    var body: some View {
        HStack(spacing: 12) {

            // Tool icon
            Image(systemName: dep.icon)
                .font(.system(.body, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Name + purpose
            VStack(alignment: .leading, spacing: 2) {
                Text(dep.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(dep.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Version + location
            VStack(alignment: .trailing, spacing: 2) {
                Text(dep.displayVersion)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                if let loc = dep.location {
                    Text(loc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .trailing)
                } else {
                    Text(dep.status == .skipped ? "Skipped" : "Not installed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Status icon
            statusIcon

            // Action menu
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.background.opacity(0.001)) // makes full row hittable
        .contentShape(Rectangle())
    }

    // MARK: Status icon

    @ViewBuilder
    private var statusIcon: some View {
        switch dep.status {
        case .installed, .updateAvailable:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        case .notInstalled:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: Context menu items

    @ViewBuilder
    private var menuItems: some View {
        // Install (default)
        Button {
            Task { await depManager.install(dep) }
        } label: {
            Label("Install", systemImage: "arrow.down.circle")
        }
        .disabled(dep.status == .installing)

        // Use system binary
        Button {
            pickSystemBinary()
        } label: {
            Label("Use system binary…", systemImage: "folder")
        }

        // Skip
        Button {
            depManager.skipDependency(id: dep.id)
        } label: {
            Label("Skip", systemImage: "minus.circle")
        }
        .disabled(dep.status == .skipped)

        // Reveal in Finder (only if installed)
        if dep.isReady, let loc = dep.location {
            Divider()
            Button {
                NSWorkspace.shared.selectFile(loc, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
        }
    }

    // MARK: System binary picker

    private func pickSystemBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Binary"
        panel.message = "Select the \(dep.displayName) binary to use."
        if panel.runModal() == .OK, let url = panel.url {
            Task { await depManager.setSystemBinary(id: dep.id, path: url) }
        }
    }
}
