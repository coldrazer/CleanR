import SwiftUI
import AppKit

/// CleanR design tokens — native & calm.
///
/// One place for spacing, radii, and surface treatment so every module
/// reads as the same app: system window/material backgrounds, hairline
/// separators, muted per-section accent used only for icons, progress,
/// and the primary action. No full-screen saturated gradients.
public enum CleanRDesign {
    // Spacing scale (points)
    public static let spaceXS: CGFloat = 4
    public static let spaceS: CGFloat = 8
    public static let spaceM: CGFloat = 12
    public static let spaceL: CGFloat = 16
    public static let spaceXL: CGFloat = 24
    public static let spaceXXL: CGFloat = 32

    // Radii — deliberately varied by role, not one radius everywhere.
    public static let radiusControl: CGFloat = 8
    public static let radiusCard: CGFloat = 10
    public static let radiusPanel: CGFloat = 12
    public static let radiusHero: CGFloat = 16

    /// Detail-pane background. System window colour so the pane matches
    /// Finder / System Settings in both appearances.
    public static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// Raised card/panel fill.
    public static var surface: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Hairline stroke for cards and panels.
    public static var separator: Color {
        Color(nsColor: .separatorColor).opacity(0.55)
    }
}

public extension View {
    /// Card surface: system control background + hairline, `radiusCard`.
    func cleanRCard() -> some View {
        background {
            RoundedRectangle(cornerRadius: CleanRDesign.radiusCard, style: .continuous)
                .fill(CleanRDesign.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: CleanRDesign.radiusCard, style: .continuous)
                        .strokeBorder(CleanRDesign.separator, lineWidth: 1)
                }
        }
    }

    /// Large list/panel surface (results tables, module checklists).
    /// Honours the Settings "Remove background colors" preference: when
    /// on, the panel is transparent and only the hairline remains.
    func cleanRPanel(removeBackgroundColors: Bool = false) -> some View {
        background {
            if removeBackgroundColors {
                RoundedRectangle(cornerRadius: CleanRDesign.radiusPanel, style: .continuous)
                    .strokeBorder(CleanRDesign.separator, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: CleanRDesign.radiusPanel, style: .continuous)
                    .fill(CleanRDesign.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: CleanRDesign.radiusPanel, style: .continuous)
                            .strokeBorder(CleanRDesign.separator, lineWidth: 1)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CleanRDesign.radiusPanel, style: .continuous))
    }
}

/// SF Symbol in a soft accent-tinted rounded square. Used for module and
/// state headers instead of a bare oversized symbol.
public struct StateIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 52

    public init(systemImage: String, tint: Color, size: CGFloat = 52) {
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .accessibilityHidden(true)
    }
}

/// Consistent page header for module screens: accent icon, title,
/// subtitle. Replaces the repeated ad-hoc 22–30pt bold titles.
public struct ModulePageHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    public init(title: String, subtitle: String? = nil, systemImage: String, tint: Color) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: CleanRDesign.spaceM) {
            StateIcon(systemImage: systemImage, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: CleanRDesign.spaceS)
        }
    }
}
