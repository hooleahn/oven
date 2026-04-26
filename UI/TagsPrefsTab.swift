import SwiftUI

struct TagsPrefsTab: View {
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var vmStore: VMStore
    @State private var editingTag: String? = nil
    @State private var newName: String = ""
    @State private var showNewTag = false
    @State private var newTagName = ""
    @State private var newTagColorIndex: Int = 0
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
                        if !t.isEmpty { tagStore.setPaletteIndex(newTagColorIndex, for: t) }
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
                            PaletteSwatchGrid(selectedIndex: $newTagColorIndex)
                        }
                        if !newTagName.isEmpty {
                            LabeledContent("Preview") {
                                let color = TagStore.paletteColor(at: newTagColorIndex)
                                Text(newTagName)
                                    .font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(color.opacity(0.25), in: Capsule())
                                    .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
                                    .foregroundStyle(color)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .frame(minWidth: 360, idealWidth: 400, minHeight: 220)
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
                newTagName = ""
                newTagColorIndex = 0
                showNewTag = true
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
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Tag name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitRename(tag) }
                    PaletteSwatchGrid(
                        selectedIndex: Binding(
                            get: { tagStore.colorIndex(for: tag) },
                            set: { tagStore.setPaletteIndex($0, for: tag) }
                        )
                    )
                    HStack {
                        Button("Save") { commitRename(tag) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("Cancel") { editingTag = nil }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            } else {
                HStack(spacing: 10) {
                    // Color swatch (click cycles to next palette color)
                    Button {
                        let current = tagStore.colorIndex(for: tag)
                        tagStore.setPaletteIndex((current + 1) % TagStore.palette.count, for: tag)
                    } label: {
                        Circle()
                            .fill(tagStore.color(for: tag))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Click to cycle color; edit row for full palette")

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
