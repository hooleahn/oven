import Foundation

// MARK: - PackerTemplateKind

enum PackerTemplateKind: String, Codable, CaseIterable {
    case fullTemplate  = "fullTemplate"   // .pkr.hcl — drives a build
    case varsFile      = "varsFile"       // .pkrvars.hcl — overrides variables

    var label: String {
        switch self {
        case .fullTemplate: return "Full Template"
        case .varsFile:     return "Template Variables"
        }
    }

    var systemImage: String {
        switch self {
        case .fullTemplate: return "doc.text"
        case .varsFile:     return "slider.horizontal.3"
        }
    }

    var fileExtension: String {
        switch self {
        case .fullTemplate: return "pkr.hcl"
        case .varsFile:     return "pkrvars.hcl"
        }
    }
}

// MARK: - PackerTemplate

struct PackerTemplate: Identifiable, Hashable {
    let id: UUID                      // from metadata sidecar (stable across reloads)
    var filename: String
    var url: URL
    var content: String               // loaded on demand
    var modifiedAt: Date
    var isBase: Bool                  // true = in defaults/ subdir (Oven-managed)
    var kind: PackerTemplateKind

    // Metadata (from sidecar .meta.json)
    var displayName: String
    var templateDescription: String
    var osName: String                // MacOSRelease.Name.rawValue, empty for vars files
    var osVersion: String             // e.g. "15.4", empty for vars files

    // Validation state (transient — not persisted)
    var validationState: ValidationState = .unknown

    enum ValidationState: Equatable, Hashable {
        case unknown
        case validating
        case valid
        case invalid(String)
    }

    // Intentionally using synthesised memberwise == and hash so SwiftUI's ForEach
    // diff detects property changes (e.g. displayName) and re-renders the row.
    // Do NOT add a custom == that only compares id — that would make rows stale.

    /// Infer kind from filename: .pkrvars.hcl → varsFile, otherwise → fullTemplate
    static func kind(for url: URL) -> PackerTemplateKind {
        url.lastPathComponent.hasSuffix(".pkrvars.hcl") ? .varsFile : .fullTemplate
    }
}
