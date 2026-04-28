import SwiftUI

// MARK: - EmptyStateRecipes

struct EmptyStateRecipes: View {
    @EnvironmentObject var theme: AppTheme

    enum RecipeTab {
        case templates, varsFiles, blocks
    }

    let tab: RecipeTab
    var onNew: () -> Void
    var onImportCirrus: (() -> Void)?

    @State private var showHelp = false

    private var headline: String {
        switch tab {
        case .templates:  return theme.funModeEnabled ? "No Recipes Yet"        : "No Packer Templates"
        case .varsFiles:  return "No Variables Files"
        case .blocks:     return "No Building Blocks"
        }
    }

    private var subtitle: String {
        switch tab {
        case .templates:
            return theme.funModeEnabled
                ? "Recipes drive Base VM builds. Create one from scratch or import a starter from Cirrus Labs."
                : "Packer templates (.pkr.hcl) drive Base VM builds. Create one from scratch or import from Cirrus Labs."
        case .varsFiles:
            return "Variables files (.pkrvars.hcl) let you override template settings per environment — e.g. staging vs. production."
        case .blocks:
            return "Building blocks are reusable provisioner snippets you can drop into any Packer template."
        }
    }

    private var systemImage: String {
        switch tab {
        case .templates: return "doc.text"
        case .varsFiles: return "slider.horizontal.3"
        case .blocks:    return "puzzlepiece"
        }
    }

    var body: some View {
        EmptyStateView(headline, systemImage: systemImage, description: subtitle) {
            HStack(spacing: 10) {
                if tab == .templates, let onImport = onImportCirrus {
                    Button {
                        onImport()
                    } label: {
                        Label("Import from Cirrus Labs", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onNew()
                    } label: {
                        Label("Create Blank Template", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        onNew()
                    } label: {
                        Label("New…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } content: {
            Button {
                showHelp = true
            } label: {
                Text("What are \(tabHelpLabel)?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp) {
                recipesHelpPopover
            }
        }
    }

    private var tabHelpLabel: String {
        switch tab {
        case .templates: return theme.funModeEnabled ? "recipes" : "Packer templates"
        case .varsFiles: return "variables files"
        case .blocks:    return "building blocks"
        }
    }

    private var helpTitle: String {
        switch tab {
        case .templates: return theme.funModeEnabled ? "What are Recipes?" : "What are Packer Templates?"
        case .varsFiles: return "What are Variables Files?"
        case .blocks:    return "What are Building Blocks?"
        }
    }

    private var helpBody: String {
        switch tab {
        case .templates:
            return "Packer templates are HCL files that describe how to build a Base VM image — what IPSW to use, which provisioners to run, and how to configure the resulting VM. Oven ships with curated base templates; you can fork and customize them freely."
        case .varsFiles:
            return "Variables files let you parameterize a template without editing it. Define different values for CPU count, disk size, or macOS version per environment and pass them to the build. Keep your templates DRY and your environments consistent."
        case .blocks:
            return "Building blocks are reusable shell script provisioners. Drag them into a template to install tools, configure settings, or run any automation — without duplicating code across templates."
        }
    }

    private var recipesHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(helpTitle)
                .font(.headline)

            Text(helpBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link("Read the docs", destination: URL(string: "https://tart.run/quick-start/")!)
                .font(.callout)
        }
        .padding(16)
        .frame(width: 320)
    }
}
