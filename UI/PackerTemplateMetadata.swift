import Foundation

// MARK: - PackerTemplateMetadata
//
// Sidecar JSON file stored alongside each .pkr.hcl or .pkrvars.hcl file.
// Filename convention: <template-stem>.pkr.meta.json
//
// Example: sequoia-15.4.pkr.hcl → sequoia-15.4.pkr.meta.json
//
// The HCL file itself also gets a comment header written on create/save,
// purely for readability in external editors — we do not parse it back.

struct PackerTemplateMetadata: Codable {
    var id: UUID
    var displayName: String
    var templateDescription: String
    var osName: String          // MacOSRelease.Name.rawValue, empty for vars files
    var osVersion: String       // e.g. "15.4", empty for vars files
    var createdAt: Date
    var schemaVersion: Int = 1
    /// Date of the last successful validation. Used to restore `.valid` state
    /// on relaunch, provided the file has not been modified since.
    var validatedAt: Date? = nil

    init(id: UUID = UUID(), displayName: String, templateDescription: String = "",
         osName: String = "", osVersion: String = "", createdAt: Date = Date(),
         validatedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.templateDescription = templateDescription
        self.osName = osName
        self.osVersion = osVersion
        self.createdAt = createdAt
        self.validatedAt = validatedAt
    }
}

// MARK: - Load / Save helpers

extension PackerTemplateMetadata {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Derives the sidecar URL for a given HCL file URL.
    /// e.g. /path/sequoia-15.4.pkr.hcl → /path/sequoia-15.4.pkr.meta.json
    static func sidecarURL(for hclURL: URL) -> URL {
        // Strip the last extension (.hcl or .hcl), then append .pkr.meta.json
        let stem = hclURL.deletingPathExtension().lastPathComponent  // "sequoia-15.4.pkr"
        return hclURL.deletingLastPathComponent()
            .appendingPathComponent("\(stem).meta.json")
    }

    /// Loads metadata for the given HCL file, or returns nil if no sidecar exists.
    static func load(for hclURL: URL) -> PackerTemplateMetadata? {
        let url = sidecarURL(for: hclURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PackerTemplateMetadata.self, from: data)
    }

    /// Saves this metadata as a sidecar next to the given HCL file.
    func save(for hclURL: URL) throws {
        let url = PackerTemplateMetadata.sidecarURL(for: hclURL)
        let data = try PackerTemplateMetadata.encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Creates a new metadata sidecar for a newly created HCL file,
    /// then writes the HCL comment header block into the file.
    static func create(for hclURL: URL, displayName: String, description: String,
                       osName: String, osVersion: String) throws -> PackerTemplateMetadata {
        let meta = PackerTemplateMetadata(
            displayName: displayName,
            templateDescription: description,
            osName: osName,
            osVersion: osVersion
        )
        try meta.save(for: hclURL)
        return meta
    }

    /// Builds the HCL comment header to prepend to template files.
    func hclCommentHeader(filename: String) -> String {
        var lines = [
            "# -------------------------",
            "# \(displayName)",
        ]
        if !templateDescription.isEmpty {
            lines.append("# \(templateDescription)")
        }
        if !osName.isEmpty {
            let ver = osVersion.isEmpty ? "" : " \(osVersion)"
            lines.append("# macOS: \(osName)\(ver)")
        }
        lines.append("# File: \(filename)")
        lines.append("# Created: \(ISO8601DateFormatter().string(from: createdAt))")
        lines.append("# ID: \(id.uuidString)")
        lines.append("# -------------------------")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
