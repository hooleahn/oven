import Foundation

/// A user-defined macOS release that doesn't appear in SOFA/IPSW.me listings.
/// Entries are shared across all OS pickers via CustomOSStore.
struct CustomOSEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var releaseName: String    // e.g. "Yuba"
    var majorVersion: Int      // e.g. 27
    var addedAt: Date

    init(id: UUID = UUID(), releaseName: String, majorVersion: Int, addedAt: Date = Date()) {
        self.id = id
        self.releaseName = releaseName
        self.majorVersion = majorVersion
        self.addedAt = addedAt
    }

    /// Short label shown in pickers: "Yuba (27)"
    var pickerLabel: String { "\(releaseName) (\(majorVersion))" }
}
