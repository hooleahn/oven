import SwiftUI

// MARK: - MenuBarMenuContent
//
// Native .menu-style MenuBarExtra content.
// Only Button, Menu, Divider, ForEach, Label, and Text are valid here —
// no custom layout, ScrollView, or gesture modifiers.
//
// Three sections:
//   1. Running — all VMs currently running or suspended (with Stop submenu)
//   2. Recent  — top 3 stopped VMs by lastStartedAt
//   3. Pinned  — up to 5 VMs the user has pinned via right-click

struct MenuBarMenuContent: View {

    var model: MenuBarViewModel

    var body: some View {
        // Kick a sync every time the menu opens.
        Color.clear.frame(width: 0, height: 0).task { model.onMenuOpen() }

        if model.runningVMs.isEmpty && model.recentVMs.isEmpty && model.pinnedVMs.isEmpty {
            Text("No Virtual Machines")
        }

        // MARK: Running
        if !model.runningVMs.isEmpty {
            Text("Running")
            ForEach(model.runningVMs) { vm in
                let label = vm.displayName.isEmpty ? vm.name : vm.displayName
                Menu {
                    Button("Open in Oven") { model.focusVM(vm) }
                    Divider()
                    Button("Stop\u{2026}", role: .destructive) { model.stopVM(vm) }
                } label: {
                    Label {
                        Text(label)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(.green)
                    }
                }
            }
            Divider()
        }

        // MARK: Recent
        if !model.recentVMs.isEmpty {
            Text("Recent")
            ForEach(model.recentVMs) { vm in
                Button(vm.displayName.isEmpty ? vm.name : vm.displayName) {
                    model.focusVM(vm)
                }
            }
            Divider()
        }

        // MARK: Pinned
        if !model.pinnedVMs.isEmpty {
            Text("Pinned")
            ForEach(model.pinnedVMs) { vm in
                Button(vm.displayName.isEmpty ? vm.name : vm.displayName) {
                    model.focusVM(vm)
                }
            }
            Divider()
        }

        // MARK: Footer
        Button("Open Oven") { model.openMainWindow() }
        SettingsLink { Text("Preferences\u{2026}") }
        Divider()
        Button("Quit Oven") { NSApp.terminate(nil) }
    }
}
