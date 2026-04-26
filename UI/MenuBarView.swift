import SwiftUI

// MARK: - MenuBarView
//
// Content for the .menu-style MenuBarExtra.
// IMPORTANT: .menu style renders as a native NSMenu, so only Button, Menu,
// Divider, ForEach, Label, and Text are valid top-level children.
// Layout containers (HStack, VStack, etc.) are ignored.

struct MenuBarView: View {

    // Passed in from OvenApp — cannot use @EnvironmentObject because
    // MenuBarExtra content runs outside the main environment hierarchy.
    var model: MenuBarViewModel
    var monitor = BuildMonitor.shared

    var body: some View {
        // Sync VM state each time the menu is opened.
        // .task fires on onAppear, which the .menu style triggers on every open.
        Color.clear
            .frame(width: 0, height: 0)
            .task { model.onMenuOpen() }

        // ── Active Builds section ────────────────────────────────────────────
        if !model.cachedActiveBuilds.isEmpty {
            Text("Builds")
            ForEach(model.cachedActiveBuilds) { vm in
                buildEntry(vm)
            }
            Divider()
        }

        // ── Virtual Machines section ─────────────────────────────────────────
        if model.cachedDisplayVMs.isEmpty {
            Text("No Virtual Machines")
        } else {
            ForEach(model.cachedDisplayVMs) { vm in
                vmEntry(vm)
            }
        }

        Divider()

        if model.cachedHasActiveVMs {
            Button("Stop All VMs…") {
                model.confirmAndStopAll()
            }
            Divider()
        }

        Button("Open Oven") {
            model.openMainWindow()
        }
    }

    // MARK: - Per-build entry

    @ViewBuilder
    private func buildEntry(_ vm: VirtualMachine) -> some View {
        let label = vm.displayName.isEmpty ? vm.name : vm.displayName
        let phase = monitor.phase.label
        let pct   = Int(monitor.progress * 100)
        Button {
            model.focusBaseVM(vm)
        } label: {
            // Native NSMenu renders Label/Text; we compose a readable string
            // since layout views are not available in .menu style.
            Label(
                "\(label)  [\(phase)]  \(pct)%",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }

    // MARK: - Per-VM entry

    @ViewBuilder
    private func vmEntry(_ vm: VirtualMachine) -> some View {
        let label = vm.displayName.isEmpty ? vm.name : vm.displayName

        switch vm.status {

        case .stopped:
            // Stopped VM: submenu lets user pick launch mode
            Menu {
                Button {
                    model.startVM(vm, mode: .native)
                } label: {
                    Label("Native Window", systemImage: "desktopcomputer")
                }

                Button {
                    model.startVM(vm, mode: .vnc)
                } label: {
                    Label("VNC / Screen Sharing", systemImage: "inset.filled.rectangle.and.person.filled")
                }

                Button {
                    model.startVM(vm, mode: .headless)
                } label: {
                    Label("Headless (SSH only)", systemImage: "terminal")
                }
            } label: {
                Label(label, systemImage: "stop.circle")
            }

        case .running:
            Menu {
                Button("Stop…", role: .destructive) {
                    model.confirmAndStopVM(vm)
                }
            } label: {
                Label {
                    Text(label)
                } icon: {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green)
                }
            }

        case .suspended:
            Menu {
                Button("Stop…", role: .destructive) {
                    model.confirmAndStopVM(vm)
                }
            } label: {
                Label {
                    Text(label)
                } icon: {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

        case .building:
            Label(label + " (Building…)", systemImage: "arrow.triangle.2.circlepath")

        case .error:
            Label(label + " (Error)", systemImage: "exclamationmark.circle.fill")
        }
    }
}
