import SwiftUI

struct TagsPrefsTab: View {
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var vmStore: VMStore
    @State private var editingTag: String? = nil
    @State private var newName: String = ""
    @State private var showNewTag = false
    @State private var newTagName = ""
    @State private var newTagColor = Color.blue
    @State private var confirmDeleteTag: String? = nil

    private var allTags: [String] { tagStore.managedTags }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tagListHeader

            if allTags.isEmpty {
                ContentUnavailableView {
                    Label("No Tags Yet", systemImage: "tag")
                } description: {
                    Text("Create a tag with the button above, or add tags to VMs from the Edit sheet.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(allTags, id: \.self) { tag in
                            tagRow(tag)
                        }
                    }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
                .padding(.horizontal, 16)
            }
        }

        .confirmationDialog(
            confirmDeleteTag.map { "Delete '\($0)'?" } ?? "Delete tag?",
            isPresented: Binding(
                get: { confirmDeleteTag != nil },
                set: { if !$0 { confirmDeleteTag = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tag = confirmDeleteTag {
                let count = vmStore.vms.filter { $0.tags.contains(tag) }.count
                Button("Delete & remove from \(count) VM\(count == 1 ? "" : "s")", role: .destructive) {
                    deleteTag(tag, removeFromVMs: true)
                }
                Button("Cancel", role: .cancel) { confirmDeleteTag = nil }
            }
        } message: {
            if let tag = confirmDeleteTag {
                let count = vmStore.vms.filter { $0.tags.contains(tag) }.count
                Text("This tag is used on \(count) VM\(count == 1 ? "" : "s"). Deleting it will also remove it from \(count == 1 ? "that VM" : "these VMs").")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Tags")
        .sheet(isPresented: $showNewTag) {
            VStack(spacing: 0) {
                HStack {
                    Text("New Tag").font(.headline)
                    Spacer()
                    Button("Cancel") { showNewTag = false }.keyboardShortcut(.escape)
                    Button("Add") {
                        let t = newTagName.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { tagStore.setColor(newTagColor, for: t) }
                        showNewTag = false
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16).background(.bar)
                Divider()
                Form {
                    Section("Tag") {
                        LabeledContent("Name") {
                            TextField("", text: $newTagName,
                                      prompt: Text("e.g. production").foregroundColor(.secondary))
                        }
                        LabeledContent("Color") {
                            ColorPicker("", selection: $newTagColor, supportsOpacity: false)
                                .labelsHidden()
                        }
                        if !newTagName.isEmpty {
                            LabeledContent("Preview") {
                                Text(newTagName)
                                    .font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(newTagColor.opacity(0.25), in: Capsule())
                                    .overlay(Capsule().stroke(newTagColor.opacity(0.5), lineWidth: 1))
                                    .foregroundStyle(newTagColor)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .frame(minWidth: 320, idealWidth: 360, minHeight: 220)
        }
    }

    private func deleteTag(_ tag: String, removeFromVMs: Bool = false) {
        tagStore.removeColor(for: tag)
        if removeFromVMs {
            for vm in vmStore.vms where vm.tags.contains(tag) {
                vmStore.update(id: vm.id) { v in
                    v.tags = v.tags.filter { $0 != tag }
                }
            }
        }
        confirmDeleteTag = nil
    }

    private func commitRename(_ old: String) {
        let t = newName.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != old else { editingTag = nil; return }
        tagStore.rename(tag: old, to: t)
        // Propagate rename to all VMs that had the old tag
        for vm in vmStore.vms where vm.tags.contains(old) {
            vmStore.update(id: vm.id) { v in
                v.tags = v.tags.map { $0 == old ? t : $0 }
            }
        }
        editingTag = nil
    }

    // MARK: - Subviews

    @ViewBuilder private var tagListHeader: some View {
        HStack {
            Text("Create and manage tags. Deleting a tag removes its color definition; optionally remove it from all VMs.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                newTagName = ""; newTagColor = .blue; showNewTag = true
            } label: {
                Label("New Tag", systemImage: "plus")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        Divider()
    }

    @ViewBuilder private func tagRow(_ tag: String) -> some View {
        VStack(spacing: 0) {
            if editingTag == tag {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { tagStore.color(for: tag) },
                        set: { tagStore.setColor($0, for: tag) }
                    ), supportsOpacity: false)
                    .labelsHidden().frame(width: 28)
                    TextField("Tag name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRename(tag) }
                    Button("Save") { commitRename(tag) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Cancel") { editingTag = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            } else {
                HStack(spacing: 10) {
                    ColorPicker("", selection: Binding(
                        get: { tagStore.color(for: tag) },
                        set: { tagStore.setColor($0, for: tag) }
                    ), supportsOpacity: false)
                    .labelsHidden().frame(width: 28)
                    HStack(spacing: 4) {
                        TagChip(tag: tag)
                        Button {
                            newName = tag; editingTag = tag
                        } label: {
                            Image(systemName: "pencil").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Rename tag")
                        Button(role: .destructive) {
                            let count = vmStore.vms.filter { $0.tags.contains(tag) }.count
                            if count > 0 { confirmDeleteTag = tag } else { deleteTag(tag) }
                        } label: {
                            Image(systemName: "trash").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete tag")
                    }
                    let count = vmStore.vms.filter { $0.tags.contains(tag) }.count
                    if count > 0 {
                        Text("\(count) VM\(count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            Divider().padding(.leading, 16)
        }
    }
}
