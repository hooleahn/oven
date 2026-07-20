import SwiftUI
import AppKit

/// Shown on first launch (or when deps are missing) while DependencyManager bootstraps.
/// Once allReady == true, the app transitions to the main window.
struct SetupView: View {
    @Bindable var depManager: DependencyManager

    @State private var storageRoot: URL = AppSettings.defaultLocalStorageRoot
    @State private var isInstalling = false
    @State private var showInstallAllAlert = false

    private var canInstallMissing: Bool {
        depManager.dependencies.contains { $0.status == .notInstalled || $0.status == .error }
    }

    private var hasMissingWithDetected: Bool {
        depManager.dependencies.contains {
            ($0.status == .notInstalled || $0.status == .error) && $0.detectedSystemPath != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Oven needs these tools to build VMs")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Text("Oven-managed components install to \(storageRoot.path).")
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
                    for dep in depManager.dependencies where dep.status == .notInstalled {
                        depManager.skipDependency(id: dep.id)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canInstallMissing || depManager.isCheckingVersions)

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

                if hasMissingWithDetected {
                    Button("Install Missing") {
                        isInstalling = true
                        Task {
                            await depManager.installMissing()
                            isInstalling = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canInstallMissing || isInstalling || depManager.isCheckingVersions)
                    .help("Use detected system binaries where found; download only the rest.")
                }

                Button("Install All") {
                    if hasMissingWithDetected {
                        showInstallAllAlert = true
                    } else {
                        isInstalling = true
                        Task {
                            await depManager.installAll()
                            isInstalling = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstallMissing || isInstalling || depManager.isCheckingVersions)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .alert("Override Detected Binaries?", isPresented: $showInstallAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Install All") {
                    isInstalling = true
                    Task {
                        await depManager.installAll()
                        isInstalling = false
                    }
                }
            } message: {
                let detected = depManager.dependencies.filter {
                    $0.detectedSystemPath != nil && ($0.status == .notInstalled || $0.status == .error)
                }
                let names = detected.map(\.displayName).joined(separator: ", ")
                Text("Oven will download and install its own copies of \(names). These will be used instead of the versions already found on this Mac.")
            }
        }
        .frame(width: 600, height: 560)
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
            var settings = AppSettings.load()
            settings.depsRoot = url.appendingPathComponent("deps", isDirectory: true)
            try? settings.save()
        }
    }
}

// MARK: - Dependency row

private struct DependencyRow: View {
    let dep: Dependency
    let depManager: DependencyManager

    @State private var showInstallOverrideAlert = false
    @State private var editingCustomPath: String = ""
    @State private var isEditingPath = false

    private var isPlugin: Bool { dep.id == "tart-packer-plugin" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Main row ──────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: dep.icon)
                    .font(.system(.body, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

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
                    if dep.isReady {
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
                        }
                    } else {
                        Text(dep.status == .skipped ? "Skipped" : "Not installed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Method picker (disabled for plugin — always managed)
                if !isPlugin {
                    Picker("", selection: methodBinding) {
                        Text("Oven-managed").tag(AppSettings.DependencyInstallSetting.Method.managed)
                        Text("Custom path").tag(AppSettings.DependencyInstallSetting.Method.custom)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .labelsHidden()
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

            // ── Expanded content (below main row) ─────────────────────────────
            if dep.installMethod == .custom && !isPlugin {
                customPathEditor
            } else if dep.installMethod == .managed, let detected = dep.detectedSystemPath, !dep.isReady {
                detectedBinaryHint(detected: detected)
            }
        }
        .background(.background.opacity(0.001))
        .contentShape(Rectangle())
        .alert("Override Detected Binary?", isPresented: $showInstallOverrideAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Install Anyway") {
                Task { await depManager.install(dep) }
            }
        } message: {
            if let detected = dep.detectedSystemPath {
                Text("Oven will download and install its own copy of \(dep.displayName), using it instead of the version already found at \(detected.path).")
            }
        }
        .onAppear { editingCustomPath = dep.customPath }
        .onChange(of: dep.customPath) { _, new in editingCustomPath = new }
    }

    // MARK: Expanded: custom path editor

    private var customPathEditor: some View {
        HStack(spacing: 8) {
            TextField("", text: $editingCustomPath,
                      prompt: Text("/usr/local/bin/\(dep.displayName)").foregroundStyle(.tertiary))
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitCustomPath() }

            Button("Browse…") { pickBinary() }
                .controlSize(.small)

            if !editingCustomPath.isEmpty {
                let exists = FileManager.default.fileExists(atPath: editingCustomPath)
                Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(exists ? .green : .red)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 52)  // align under name text (icon 24 + gap 12 + 16 padding)
        .padding(.bottom, 10)
    }

    // MARK: Expanded: detected binary hint

    private func detectedBinaryHint(detected: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Found at \(detected.path)")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Use this") {
                Task { await depManager.useDetectedBinary(id: dep.id) }
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 52)
        .padding(.bottom, 10)
    }

    // MARK: Method binding

    private var methodBinding: Binding<AppSettings.DependencyInstallSetting.Method> {
        Binding(
            get: { dep.installMethod },
            set: { newMethod in
                Task {
                    // When switching to custom, pre-fill with detected path if available
                    if newMethod == .custom, let detected = dep.detectedSystemPath {
                        await depManager.setInstallMethod(id: dep.id, to: .custom, customPath: detected.path)
                    } else {
                        await depManager.setInstallMethod(id: dep.id, to: newMethod)
                    }
                }
            }
        )
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
        Button {
            if dep.detectedSystemPath != nil && dep.installMethod == .managed {
                showInstallOverrideAlert = true
            } else {
                Task { await depManager.install(dep) }
            }
        } label: {
            Label("Download & Install", systemImage: "arrow.down.circle")
        }
        .disabled(dep.status == .installing)

        if let detected = dep.detectedSystemPath {
            Button {
                Task { await depManager.useDetectedBinary(id: dep.id) }
            } label: {
                Label("Use \(detected.lastPathComponent) at \(detected.deletingLastPathComponent().path)",
                      systemImage: "checkmark.seal")
            }
        }

        Button {
            pickBinary()
        } label: {
            Label("Browse for binary…", systemImage: "folder")
        }

        if !isPlugin {
            Divider()
            Button {
                depManager.skipDependency(id: dep.id)
            } label: {
                Label("Skip", systemImage: "minus.circle")
            }
            .disabled(dep.status == .skipped)
        }

        if dep.isReady, let loc = dep.location {
            Divider()
            Button {
                NSWorkspace.shared.selectFile(loc, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
        }
    }

    // MARK: Helpers

    private func commitCustomPath() {
        let path = editingCustomPath.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await depManager.setInstallMethod(id: dep.id, to: .custom, customPath: path) }
    }

    private func pickBinary() {
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
