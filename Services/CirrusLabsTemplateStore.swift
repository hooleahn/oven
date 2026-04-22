import Foundation

// MARK: - CirrusLabsVanillaTemplate
// Represents a single "vanilla" Packer template from the CirrusLabs public repo.
// Content is fetched lazily from GitHub when the user requests a copy.

struct CirrusLabsVanillaTemplate: Identifiable, Sendable {
    let id: String          // stable slug, e.g. "vanilla-sequoia"
    let displayName: String // e.g. "Vanilla Sequoia"
    let osName: String      // MacOSRelease.Name.rawValue, e.g. "macOS 15 Sequoia"
    let osVersion: String   // e.g. "15.x"
    let description: String
    /// Raw URL to fetch the HCL content from GitHub.
    let rawURL: URL
    /// Human-readable link to the GitHub source.
    let githubURL: URL
    /// Default filename when copied to the user's templates folder.
    var defaultFilename: String { "\(id).pkr.hcl" }
}

// MARK: - CirrusLabsTemplateStore

@MainActor
final class CirrusLabsTemplateStore: ObservableObject {

    // MARK: Static catalogue

    static let vanillaTemplates: [CirrusLabsVanillaTemplate] = [
        CirrusLabsVanillaTemplate(
            id: "vanilla-tahoe",
            displayName: "Vanilla Tahoe",
            osName: "macOS 26 Tahoe",
            osVersion: "26.x",
            description: "Clean macOS 26 Tahoe install via Tart with basic CI setup.",
            rawURL: URL(string: "https://raw.githubusercontent.com/cirruslabs/macos-image-templates/main/templates/vanilla-tahoe.pkr.hcl")!,
            githubURL: URL(string: "https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-tahoe.pkr.hcl")!
        ),
        CirrusLabsVanillaTemplate(
            id: "vanilla-sequoia",
            displayName: "Vanilla Sequoia",
            osName: "macOS 15 Sequoia",
            osVersion: "15.x",
            description: "Clean macOS 15 Sequoia install via Tart with basic CI setup.",
            rawURL: URL(string: "https://raw.githubusercontent.com/cirruslabs/macos-image-templates/main/templates/vanilla-sequoia.pkr.hcl")!,
            githubURL: URL(string: "https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-sequoia.pkr.hcl")!
        ),
        CirrusLabsVanillaTemplate(
            id: "vanilla-sonoma",
            displayName: "Vanilla Sonoma",
            osName: "macOS 14 Sonoma",
            osVersion: "14.x",
            description: "Clean macOS 14 Sonoma install via Tart with basic CI setup.",
            rawURL: URL(string: "https://raw.githubusercontent.com/cirruslabs/macos-image-templates/main/templates/vanilla-sonoma.pkr.hcl")!,
            githubURL: URL(string: "https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-sonoma.pkr.hcl")!
        ),
        CirrusLabsVanillaTemplate(
            id: "vanilla-ventura",
            displayName: "Vanilla Ventura",
            osName: "macOS 13 Ventura",
            osVersion: "13.x",
            description: "Clean macOS 13 Ventura install via Tart with basic CI setup.",
            rawURL: URL(string: "https://raw.githubusercontent.com/cirruslabs/macos-image-templates/main/templates/vanilla-ventura.pkr.hcl")!,
            githubURL: URL(string: "https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-ventura.pkr.hcl")!
        ),
        CirrusLabsVanillaTemplate(
            id: "vanilla-monterey",
            displayName: "Vanilla Monterey",
            osName: "macOS 12 Monterey",
            osVersion: "12.x",
            description: "Clean macOS 12 Monterey install via Tart with basic CI setup.",
            rawURL: URL(string: "https://raw.githubusercontent.com/cirruslabs/macos-image-templates/main/templates/vanilla-monterey.pkr.hcl")!,
            githubURL: URL(string: "https://github.com/cirruslabs/macos-image-templates/blob/main/templates/vanilla-monterey.pkr.hcl")!
        ),
    ]

    // MARK: - Fetch content

    /// Downloads the raw HCL content for the given template from GitHub.
    static func fetchContent(for template: CirrusLabsVanillaTemplate) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: template.rawURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }
        return content
    }

    enum FetchError: LocalizedError {
        case badStatus(Int)
        case invalidEncoding

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "HTTP \(code) fetching template from GitHub."
            case .invalidEncoding: return "Could not decode template content as UTF-8."
            }
        }
    }
}
