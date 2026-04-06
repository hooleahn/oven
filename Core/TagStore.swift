import SwiftUI

// MARK: - TagStore

/// Persists tag → hex colour mappings.
/// Injected as an environment object so TagChip and TagPickerField
/// can read colours without prop-drilling.
@MainActor
@Observable
final class TagStore: ObservableObject {

    private(set) var colors: [String: String] = [:]   // tag → hex

    private var storageURL: URL {
        AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("tag-colors.json")
    }

    init() { load() }

    // MARK: - Public API

    func color(for tag: String) -> Color {
        if let hex = colors[tag], let c = Color(hex: hex) { return c }
        return tagColor(for: tag)          // deterministic fallback
    }

    func setColor(_ color: Color, for tag: String) {
        colors[tag] = color.hexString
        save()
    }

    func removeColor(for tag: String) {
        colors.removeValue(forKey: tag)
        save()
    }

    func rename(tag: String, to newName: String) {
        guard let hex = colors[tag] else { return }
        colors.removeValue(forKey: tag)
        colors[newName] = hex
        save()
    }

    /// All tags that have an explicit colour assigned.
    var managedTags: [String] {
        colors.keys.sorted()
    }

    // MARK: - Persistence

    private func load() {
        colors = AppDatabase.shared.readOrDefault(.tagColors, default: [:])
    }

    private func save() {
        AppDatabase.shared.writeSilently(colors, to: .tagColors)
    }
}

// MARK: - Color hex helpers

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }

    var hexString: String {
        // Convert to sRGB first — system colors like .blue are catalog/dynamic
        // colors that crash if you call redComponent without colorspace conversion.
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else {
            return "0000FF"  // fallback to blue if conversion fails
        }
        return String(format: "%02X%02X%02X",
                      Int(rgb.redComponent   * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent  * 255))
    }
}
