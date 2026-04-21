import SwiftUI

// MARK: - Spacing

/// Consistent spacing scale used throughout Oven.
enum Spacing {
    /// 4 pt — tight gaps between related items (e.g. icon + label)
    static let xs: CGFloat = 4
    /// 8 pt — small internal padding (e.g. between list row elements)
    static let sm: CGFloat = 8
    /// 12 pt — standard component padding
    static let md: CGFloat = 12
    /// 16 pt — section padding, toolbar insets
    static let lg: CGFloat = 16
    /// 24 pt — between major sections
    static let xl: CGFloat = 24
    /// 32 pt — page-level margins
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

/// Consistent corner radius tokens used throughout Oven.
enum CornerRadius {
    /// 12 pt — card containers
    static let card: CGFloat = 12
    /// 8 pt — buttons, text fields
    static let button: CGFloat = 8
    /// 10 pt — thumbnail images
    static let thumbnail: CGFloat = 10
    /// 6 pt — chips, badges, small pills
    static let chip: CGFloat = 6
}

// MARK: - Typography

extension Font {
    /// Card primary title — body weight semibold
    static let cardTitle: Font = .system(.body, design: .default, weight: .semibold)
    /// Card secondary label — caption
    static let cardSubtitle: Font = .caption
    /// Monospaced caption for technical identifiers (build IDs, tart names, etc.)
    static let cardMono: Font = .system(.caption, design: .monospaced)
    /// Section headers in lists and forms
    static let sectionHeader: Font = .system(.headline, design: .default, weight: .semibold)
}

// MARK: - Semantic Colors

extension Color {
    /// Running VM accent — matches the app accent color
    static let vmRunning: Color = .accentColor
    /// Stopped / idle VM — secondary text color
    static let vmStopped: Color = .secondary
    /// VM currently building — purple
    static let vmBuilding: Color = .purple
    /// Default card border — very subtle separator
    static let cardBorder: Color = .primary.opacity(0.08)
    /// Selected card border — full accent color
    static let cardSelected: Color = .accentColor
}

// MARK: - CardStyle ViewModifier

/// Applies consistent card background, border and shadow for any card-shaped view.
///
/// Usage:
/// ```swift
/// myView.cardStyle(isSelected: isSelected)
/// ```
struct CardStyle: ViewModifier {
    let isSelected: Bool
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.card)
                    .strokeBorder(
                        isSelected ? Color.cardSelected : Color.cardBorder,
                        lineWidth: isSelected ? 3 : 0.5
                    )
            )
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(0.3)
                    : .black.opacity(isHovered ? 0.08 : 0.04),
                radius: isSelected ? 8 : (isHovered ? 4 : 2)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .brightness(isHovered ? 0.03 : 0)
    }
}

extension View {
    /// Applies the standard Oven card styling (background, border, shadow, hover effects).
    func cardStyle(isSelected: Bool, isHovered: Bool = false) -> some View {
        modifier(CardStyle(isSelected: isSelected, isHovered: isHovered))
    }
}


