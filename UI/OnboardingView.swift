import SwiftUI

// MARK: - OnboardingPage model

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let diagram: Diagram?

    enum Diagram {
        case overview
        case installer
        case build
        case clone
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var onDismiss: (() -> Void)?

    private static let pagesStatic: [OnboardingPage] = [
        OnboardingPage(
            icon: "oven.fill",
            iconColor: .orange,
            title: "Welcome to Oven",
            description: "Oven makes it easy to build, manage, and distribute macOS virtual machines on Apple Silicon. Powered by Tart and Packer, it gives you a full VM lifecycle — from downloading macOS to distributing images via a container registry.",
            diagram: .overview
        ),
        OnboardingPage(
            icon: "arrow.down.circle.fill",
            iconColor: .blue,
            title: "Download macOS",
            description: "Start by downloading a macOS IPSW firmware directly from Apple. Oven fetches the latest signed releases and stores them locally so you can build Base VMs offline.",
            diagram: .installer
        ),
        OnboardingPage(
            icon: "shippingbox.fill",
            iconColor: .purple,
            title: "Build a Base VM",
            description: "Use a Packer template to automate the full macOS setup — including user creation, SSH, and software installs. Oven runs the build and shows live output so you always know what's happening.",
            diagram: .build
        ),
        OnboardingPage(
            icon: "square.on.square.fill",
            iconColor: .green,
            title: "Clone & Share VMs",
            description: "Clone Base VMs instantly for development, CI, or testing. Push images to a container registry so your whole team can pull them. Each VM is isolated, fast, and always starts from a clean state.",
            diagram: .clone
        )
    ]

    private let pages: [OnboardingPage] = pagesStatic

    var body: some View {
        VStack(spacing: 0) {
            // Page content — manual paging with slide transition
            ZStack {
                SwiftUI.ForEach(0..<pages.count, id: \.self) { index in
                    let page = pages[index]
                    let isCurrent = index == currentPage
                    let xOffset = CGFloat(index - currentPage) * 620.0

                    pageView(page)
                        .opacity(isCurrent ? 1 : 0)
                        .offset(x: xOffset)
                        .id(index)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            .clipped()

            Divider()

            // Bottom bar
            HStack(spacing: 16) {
                // Skip
                Button("Skip") { complete() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(currentPage < pages.count - 1 ? 1 : 0)

                Spacer()

                // Page dots
                HStack(spacing: 6) {
                    SwiftUI.ForEach(0..<pages.count, id: \.self) { (i: Int) in
                        let isCurrent = currentPage == i
                        Circle()
                            .fill(isCurrent ? Color.accentColor : Color.secondary)
                            .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 8 : 6)
                    }
                }

                Spacer()

                // Next / Get Started
                Button(currentPage < pages.count - 1 ? "Next" : "Get Started") {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        complete()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .frame(width: 620, height: 520)
    }

    // MARK: - Page layout

    private func pageView(_ page: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Icon
                ZStack {
                    Circle()
                        .fill(page.iconColor.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: page.icon)
                        .font(.system(.largeTitle, weight: .medium))
                        .foregroundStyle(page.iconColor)
                }
                .padding(.top, 36)
                .padding(.bottom, 20)

                // Title
                Text(page.title)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Description
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                // Optional diagram
                if let diagram = page.diagram {
                    switch diagram {
                    case .overview:
                        OnboardingOverviewDiagram()
                            .padding(.top, 24)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                    case .installer:
                        OnboardingInstallerDiagram()
                            .padding(.top, 24)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                    case .build:
                        OnboardingBuildDiagram()
                            .padding(.top, 24)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                    case .clone:
                        OnboardingCloneDiagram()
                            .padding(.top, 24)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func complete() {
        hasCompletedOnboarding = true
        onDismiss?()
    }
}

// MARK: - Diagram: Overview

private struct OnboardingOverviewDiagram: View {
    private let steps: [(icon: String, color: Color, label: String)] = [
        ("arrow.down.circle.fill", .blue,   "Download"),
        ("shippingbox.fill",       .purple, "Build"),
        ("square.on.square.fill",  .green,  "Clone"),
        ("externaldrive.connected.to.line.below.fill", .orange, "Distribute"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 0) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(step.color.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: step.icon)
                                .font(.title3)
                                .foregroundStyle(step.color)
                        }
                        Text(step.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if index < steps.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 18) // align with icon center
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Diagram: Installer

private struct OnboardingInstallerDiagram: View {
    var body: some View {
        HStack(spacing: 16) {
            diagramCard(icon: "globe", color: .blue, title: "ipsw.me", subtitle: "Apple's servers")
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            diagramCard(icon: "arrow.down.circle.fill", color: .blue, title: "Oven", subtitle: "Manages download")
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            diagramCard(icon: "internaldrive.fill", color: .secondary, title: "Local IPSW", subtitle: "Stored on disk")
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Diagram: Build

private struct OnboardingBuildDiagram: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                diagramCard(icon: "doc.text.fill",   color: .purple, title: "HCL Template", subtitle: "Your recipe")
                Image(systemName: "plus").foregroundStyle(.tertiary).font(.caption)
                diagramCard(icon: "internaldrive.fill", color: .blue, title: "IPSW", subtitle: "macOS firmware")
            }
            Image(systemName: "arrow.down").foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                diagramCard(icon: "hammer.fill",        color: .orange, title: "Packer", subtitle: "Runs the build")
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).font(.caption)
                diagramCard(icon: "shippingbox.fill",   color: .purple, title: "Base VM", subtitle: "Golden image")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Diagram: Clone

private struct OnboardingCloneDiagram: View {
    var body: some View {
        HStack(spacing: 16) {
            diagramCard(icon: "shippingbox.fill", color: .purple, title: "Base VM", subtitle: "Golden image")
            VStack(spacing: 6) {
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            }
            VStack(spacing: 8) {
                miniCard(icon: "desktopcomputer", color: .green, label: "Dev VM")
                miniCard(icon: "desktopcomputer", color: .green, label: "CI VM")
                miniCard(icon: "desktopcomputer", color: .green, label: "Test VM")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func miniCard(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Shared diagram card helper

private func diagramCard(icon: String, color: Color, title: String, subtitle: String) -> some View {
    VStack(spacing: 6) {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.10))
                .frame(width: 48, height: 48)
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
        }
        Text(title).font(.caption2).fontWeight(.medium)
        Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
    }
}
