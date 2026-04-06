import SwiftUI

/// Shown on first launch (or when deps are missing) while DependencyManager bootstraps.
/// Once allReady == true, the app transitions to the main window.
struct SetupView: View {
    var depManager: DependencyManager

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 8) {
                Image(systemName: "oven")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Setting up Oven")
                    .font(.title2)
                    .fontWeight(.medium)
                Text("Downloading required tools. This only happens once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)

            // Dependency rows
            VStack(spacing: 6) {
                ForEach(depManager.dependencies) { dep in
                    DependencyRow(dependency: dep)
                }
            }
            .padding(.horizontal, 40)

            // Install log (collapsed unless there's content)
            if !depManager.installLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(depManager.installLog.indices, id: \.self) { i in
                            Text(depManager.installLog[i])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 40)
                .padding(.top, 20)
            }

            Spacer()

            // Footer status
            HStack {
                if depManager.isCheckingVersions {
                    ProgressView().controlSize(.small)
                    Text("Working…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if depManager.allReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All dependencies ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - Dependency row

private struct DependencyRow: View {
    let dependency: Dependency

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                switch dependency.status {
                case .installed, .updateAvailable:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .installing:
                    ProgressView().controlSize(.small)
                case .notInstalled:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 18)

            // Name
            Text(dependency.displayName)
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            // Version or status label
            Group {
                switch dependency.status {
                case .installed:
                    Text(dependency.currentVersion ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                case .installing:
                    Text("Installing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .notInstalled:
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                case .updateAvailable:
                    Text("Update available")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .error:
                    Text("Failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
