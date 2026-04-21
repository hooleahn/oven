import SwiftUI

// MARK: - LaunchModeSheet

struct LaunchModeSheet: View {
    let vm: VirtualMachine
    let onLaunch: (TartService.RunMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Start \"\(vm.displayName.isEmpty ? vm.name : vm.displayName)\"")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding(16).background(.bar)
            Divider()

            VStack(spacing: 12) {
                Text("How would you like to start this VM?")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LaunchOptionButton(
                    icon: "desktopcomputer",
                    title: "Native",
                    description: "Open in Tart window"
                ) { onLaunch(.native); dismiss() }

                LaunchOptionButton(
                    icon:"inset.filled.rectangle.and.person.filled",
                    title: "VNC / Screen Sharing",
                    description: "Start headless and connect via Screen Sharing"
                ) { onLaunch(.vnc); dismiss() }

                LaunchOptionButton(
                    icon: "terminal",
                    title: "Headless (SSH only)",
                    description: "Start with no display — access via SSH at port 22"
                ) { onLaunch(.headless); dismiss() }
                
                LaunchOptionButton(
                    icon: "display.and.screwdriver",
                    title: "Recovery (Native only)",
                    description: "Start on Recovery Mode"
                ) { onLaunch(.recovery); dismiss() }
            }
            .padding(20)
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 280)
    }
}

private struct LaunchOptionButton: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
