import SwiftUI

// MARK: - Tag colour (deterministic fallback)

func tagColor(for tag: String) -> Color {
    let palette: [Color] = [
        .blue, .purple, .indigo, .teal, .cyan,
        .green, .mint, .orange, .red, .pink,
    ]
    var hash = 5381
    for char in tag.unicodeScalars { hash = hash &* 31 &+ Int(char.value) }
    return palette[abs(hash) % palette.count]
}

// MARK: - TagChip

struct TagChip: View {
    let tag: String
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil
    @EnvironmentObject var tagStore: TagStore

    var body: some View {
        HStack(spacing: 3) {
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if removable {
                Button { onRemove?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tagStore.color(for: tag).opacity(0.18), in: Capsule())
        .foregroundStyle(tagStore.color(for: tag))
    }
}

// MARK: - TagPickerField

struct TagPickerField: View {
    @Binding var tags: [String]
    var existingTags: [String] = []
    @EnvironmentObject var tagStore: TagStore
    @State private var input = ""
    @State private var showSuggestions = false
    @State private var pendingNewTag: String? = nil   // tag awaiting color pick
    @State private var pendingColor: Color = .blue

    private var suggestions: [String] {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return existingTags
            .filter { !tags.contains($0) && $0.lowercased().hasPrefix(q) }
            .prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                            TagChip(tag: tag, removable: true) {
                                tags.remove(at: index)
                            }
                        }
                    }
                }
            }

            // Inline color picker for new tags
            if let newTag = pendingNewTag {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Color for \"\(newTag)\"")
                            .font(.caption).foregroundStyle(.secondary)
                        ColorPicker("", selection: $pendingColor, supportsOpacity: false)
                            .labelsHidden().frame(width: 28)
                        Button("Set color") {
                            tagStore.setColor(pendingColor, for: newTag)
                            tags.append(newTag)
                            pendingNewTag = nil
                        }
                        .buttonStyle(.borderedProminent).controlSize(.mini)
                        Button("Skip") {
                            // Register with deterministic color so it appears in Preferences
                            tagStore.setColor(tagColor(for: newTag), for: newTag)
                            tags.append(newTag)
                            pendingNewTag = nil
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 6) {
                TextField("Add tag…", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit { commitInput() }
                    .onChange(of: input) { _, v in
                        showSuggestions = !v.trimmingCharacters(in: .whitespaces).isEmpty
                    }
                if !input.isEmpty {
                    Button("Add") { commitInput() }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }

            if showSuggestions && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            Button {
                                tags.append(s); input = ""; showSuggestions = false
                            } label: {
                                TagChip(tag: s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func commitInput() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { input = ""; return }
        input = ""
        showSuggestions = false
        // If tag already has a color, just add it; otherwise prompt
        if tagStore.colors[t] != nil {
            tags.append(t)
        } else {
            pendingColor = tagColor(for: t)   // pre-seed with deterministic color
            pendingNewTag = t
        }
    }
}
