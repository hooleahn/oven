import SwiftUI
import AppKit

// MARK: - TagChip

struct TagChip: View {
    let tag: String
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil
    var size: Font = .caption
    /// Called on normal tap (replace filter with just this tag).
    var onTap: ((String) -> Void)? = nil
    /// Called on shift-tap (add/toggle tag in active filter).
    var onShiftTap: ((String) -> Void)? = nil
    /// Called from context menu: Rename.
    var onRename: ((String) -> Void)? = nil
    /// Called from context menu: Remove from VM.
    var onRemoveFromVM: ((String) -> Void)? = nil
    /// Called from context menu: Delete tag everywhere.
    var onDeleteEverywhere: ((String) -> Void)? = nil

    @Environment(TagStore.self) private var tagStore

    var body: some View {
        HStack(spacing: 3) {
            Text(tag)
                .font(size.weight(.medium))
                .lineLimit(1)
            if removable {
                Button { onRemove?() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.xs + 2) // 6 pt
        .padding(.vertical, 2)
        .background(tagStore.color(for: tag).opacity(0.18), in: Capsule())
        .foregroundStyle(tagStore.color(for: tag))
        .contentShape(Capsule())
        .accessibilityLabel("Tag: \(tag)")
        .accessibilityHint("Double-tap to filter by this tag, option-double-tap to remove")
        .ifLet(onTap != nil || onShiftTap != nil) { view in
            view
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        onShiftTap?(tag)
                    } else {
                        onTap?(tag)
                    }
                }
        }
        .contextMenu {
            if let onRename {
                Button("Rename…") { onRename(tag) }
            }
            if let onTap {
                Button("Filter by Tag") { onTap(tag) }
            }
            colorChangeSubmenu
            if onRename != nil || onRemoveFromVM != nil || onDeleteEverywhere != nil {
                Divider()
            }
            if let onRemoveFromVM {
                Button("Remove from VM") { onRemoveFromVM(tag) }
            }
            if let onDeleteEverywhere {
                Button("Delete Tag Everywhere", role: .destructive) { onDeleteEverywhere(tag) }
            }
        }
    }

    @ViewBuilder private var colorChangeSubmenu: some View {
        Menu("Change Color") {
            ForEach(0..<TagStore.palette.count, id: \.self) { i in
                Button {
                    tagStore.setPaletteIndex(i, for: tag)
                } label: {
                    HStack {
                        Circle()
                            .fill(TagStore.palette[i])
                            .frame(width: 12, height: 12)
                        Text("Color \(i + 1)")
                        if tagStore.colorIndex(for: tag) == i {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helper modifier

private extension View {
    @ViewBuilder
    func ifLet(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - PaletteSwatchGrid

/// A horizontal row of colored circle swatches for palette selection.
struct PaletteSwatchGrid: View {
    @Binding var selectedIndex: Int
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TagStore.palette.count, id: \.self) { i in
                Button {
                    selectedIndex = i
                    onSelect?(i)
                } label: {
                    ZStack {
                        Circle()
                            .fill(TagStore.palette[i])
                            .frame(width: 22, height: 22)
                        if selectedIndex == i {
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Color \(i + 1)")
            }
        }
    }
}

// MARK: - TagPickerField

struct TagPickerField: View {
    @Binding var tags: [String]
    var existingTags: [String] = []
    @Environment(TagStore.self) private var tagStore
    @State private var input = ""
    @FocusState private var isFieldFocused: Bool
    @State private var isHoveringSuggestions = false
    @State private var selectedSuggestionIndex: Int? = nil
    @State private var pendingNewTag: String? = nil
    @State private var pendingColorIndex: Int = 0

    private var suggestions: [String] {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        let available = existingTags.filter { !tags.contains($0) }
        guard !available.isEmpty else { return [] }
        if q.isEmpty {
            return Array(available.prefix(5))
        }
        return available.filter { $0.lowercased().hasPrefix(q) }.prefix(8).map { $0 }
    }

    private var showSuggestions: Bool {
        (isFieldFocused || isHoveringSuggestions) && !suggestions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                            TagChip(tag: tag, removable: true) {
                                tags.remove(at: index)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            // Inline palette picker for new tags
            if let newTag = pendingNewTag {
                HStack(spacing: 8) {
                    Text("Color for \"\(newTag)\"")
                        .font(.caption).foregroundStyle(.secondary)
                    PaletteSwatchGrid(selectedIndex: $pendingColorIndex)
                    Button("Set") {
                        tagStore.setPaletteIndex(pendingColorIndex, for: newTag)
                        tags.append(newTag)
                        pendingNewTag = nil
                    }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                    Button("Skip") {
                        let hash = newTag.unicodeScalars.reduce(5381) { $0 &* 31 &+ Int($1.value) }
                        tagStore.setPaletteIndex(abs(hash) % TagStore.palette.count, for: newTag)
                        tags.append(newTag)
                        pendingNewTag = nil
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.button))
            }

            HStack(spacing: 6) {
                TextField("Add tag…", text: $input)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        if let idx = selectedSuggestionIndex, idx < suggestions.count {
                            applyTag(suggestions[idx])
                        } else {
                            commitInput()
                        }
                    }
                    .onChange(of: input) { _, _ in selectedSuggestionIndex = nil }
                    .onKeyPress(.downArrow) {
                        guard !suggestions.isEmpty else { return .ignored }
                        selectedSuggestionIndex = selectedSuggestionIndex
                            .map { min($0 + 1, suggestions.count - 1) } ?? 0
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard let idx = selectedSuggestionIndex else { return .ignored }
                        selectedSuggestionIndex = idx > 0 ? idx - 1 : nil
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        let tag = selectedSuggestionIndex.map { suggestions[$0] } ?? suggestions.first
                        guard let tag else { return .ignored }
                        applyTag(tag)
                        return .handled
                    }
                if !input.isEmpty {
                    Button("Add") { commitInput() }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }

            if showSuggestions {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(input.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "Available tags" : "Matching tags")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("↓↑ navigate · ↵ or Tab to apply")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 2)
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, tag in
                                Button { applyTag(tag) } label: {
                                    TagChip(tag: tag)
                                        .overlay {
                                            if selectedSuggestionIndex == i {
                                                Capsule().strokeBorder(.primary.opacity(0.45), lineWidth: 1.5)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.button))
                .onHover { isHoveringSuggestions = $0 }
            }
        }
    }

    private func applyTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        input = ""
        selectedSuggestionIndex = nil
        isHoveringSuggestions = false
    }

    private func commitInput() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { input = ""; return }
        input = ""
        selectedSuggestionIndex = nil
        if tagStore.colorIndices[t] != nil {
            tags.append(t)
        } else {
            let hash = t.unicodeScalars.reduce(5381) { $0 &* 31 &+ Int($1.value) }
            pendingColorIndex = abs(hash) % TagStore.palette.count
            pendingNewTag = t
        }
    }
}
