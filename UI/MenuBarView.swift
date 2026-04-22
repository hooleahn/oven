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

    var body: some View {
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
