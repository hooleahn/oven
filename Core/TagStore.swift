import SwiftUI

// MARK: - OKLCH → sRGB conversion

/// Convert OKLCH perceptual colour coordinates to a SwiftUI Color (sRGB).
/// L ∈ [0, 1], C ∈ [0, 0.4], H ∈ [0, 360°)
func oklchToColor(L: Double, C: Double, H: Double) -> Color {
    let hRad = H * .pi / 180.0
    let a = C * cos(hRad)
    let b = C * sin(hRad)

    // OKLab → linear sRGB (Björn Ottosson's formula)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b

    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_

    let r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let bC = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    // Gamma-compress to sRGB
    func linearToSRGB(_ c: Double) -> Double {
        let clamped = max(0, min(1, c))
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }
    return Color(.sRGB,
                 red:   linearToSRGB(r),
                 green: linearToSRGB(g),
                 blue:  linearToSRGB(bC),
                 opacity: 1)
}

// MARK: - Fixed Palette

extension TagStore {
    /// Eight perceptually-uniform hues, all at the same lightness/chroma.
    static let palette: [Color] = (0..<9).map { i in
        oklchToColor(L: 0.65, C: 0.14, H: Double(i) * 45.0)
    }

    /// Return the palette color for a given index (clamped to valid range).
    static func paletteColor(at index: Int) -> Color {
        let i = max(0, min(index, palette.count - 1))
        return palette[i]
    }

    /// Find the nearest palette index for an arbitrary Color by comparing
    /// RGB distances in sRGB space.
    static func nearestPaletteIndex(for color: Color) -> Int {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent

        var bestIndex = 0
        var bestDist = Double.infinity
        for (i, paletteColor) in palette.enumerated() {
            guard let pc = NSColor(paletteColor).usingColorSpace(.sRGB) else { continue }
            let dr = Double(r - pc.redComponent)
            let dg = Double(g - pc.greenComponent)
            let db = Double(b - pc.blueComponent)
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }
}

// MARK: - TagStore

/// Persists tag → palette-index mappings.
/// Injected as an environment object so TagChip and TagPickerField
/// can read colours without prop-drilling.
@MainActor
@Observable
final class TagStore {

    /// tag → palette index (0-based into `TagStore.palette`).
    private(set) var colorIndices: [String: Int] = [:]

    init() { load() }

    // MARK: - Public API

    func color(for tag: String) -> Color {
        if let idx = colorIndices[tag] {
            return TagStore.paletteColor(at: idx)
        }
        // Deterministic fallback using name hash
        var hash = 5381
        for char in tag.unicodeScalars { hash = hash &* 31 &+ Int(char.value) }
        return TagStore.paletteColor(at: abs(hash) % TagStore.palette.count)
    }

    func colorIndex(for tag: String) -> Int {
        if let idx = colorIndices[tag] { return idx }
        var hash = 5381
        for char in tag.unicodeScalars { hash = hash &* 31 &+ Int(char.value) }
        return abs(hash) % TagStore.palette.count
    }

    func setColor(_ color: Color, for tag: String) {
        colorIndices[tag] = TagStore.nearestPaletteIndex(for: color)
        save()
    }

    func setPaletteIndex(_ index: Int, for tag: String) {
        colorIndices[tag] = max(0, min(index, TagStore.palette.count - 1))
        save()
    }

    func removeColor(for tag: String) {
        colorIndices.removeValue(forKey: tag)
        save()
    }

    func rename(tag: String, to newName: String) {
        guard let idx = colorIndices[tag] else { return }
        colorIndices.removeValue(forKey: tag)
        colorIndices[newName] = idx
        save()
    }

    /// All tags that have an explicit colour assigned.
    var managedTags: [String] {
        colorIndices.keys.sorted()
    }

    // MARK: - Persistence

    private func load() {
        // Try loading new index-based format first
        let indices: [String: Int] = AppDatabase.shared.readOrDefault(.tagColorIndices, default: [:])
        if !indices.isEmpty {
            colorIndices = indices
            return
        }
        // Migrate from old hex-based format
        let oldColors: [String: String] = AppDatabase.shared.readOrDefault(.tagColors, default: [:])
        if !oldColors.isEmpty {
            var migrated: [String: Int] = [:]
            for (tag, hex) in oldColors {
                if let c = Color(hex: hex) {
                    migrated[tag] = TagStore.nearestPaletteIndex(for: c)
                }
            }
            colorIndices = migrated
            save()
        }
    }

    private func save() {
        AppDatabase.shared.writeSilently(colorIndices, to: .tagColorIndices)
    }
}

// MARK: - Color hex helpers (kept for migration)

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
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else {
            return "0000FF"
        }
        return String(format: "%02X%02X%02X",
                      Int(rgb.redComponent   * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent  * 255))
    }
}
