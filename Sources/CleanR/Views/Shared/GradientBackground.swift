import SwiftUI
import AppKit

extension Color {
    /// A color that resolves to `light` or `dark` based on the active
    /// appearance, so the same value renders correctly in both Light and Dark
    /// without threading `colorScheme` through every view.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Per-section identity for the 22 modules.
///
/// Native & calm: the detail pane sits on the system window background
/// with only a faint wash of the section hue at the top. The accent is
/// reserved for sidebar icons, progress, and the primary action — it is
/// never a full-screen saturated gradient. `gradient` / `buttonGradient`
/// keep their historical names and types so existing call sites compile
/// unchanged; their values are now near-flat.
public enum ModuleTheme {
    case smartScan
    case cleanup
    case protection
    case performance
    case applications
    case files
    case settings

    /// Muted, desaturated section hues. Distinct enough to tell sections
    /// apart in the sidebar, quiet enough on system backgrounds.
    public var accentColor: Color {
        switch self {
        case .smartScan: Color(red: 0.22, green: 0.42, blue: 0.72)
        case .cleanup: Color(red: 0.16, green: 0.48, blue: 0.33)
        case .protection: Color(red: 0.68, green: 0.28, blue: 0.24)
        case .performance: Color(red: 0.62, green: 0.44, blue: 0.08)
        case .applications: Color(red: 0.42, green: 0.36, blue: 0.62)
        case .files: Color(red: 0.14, green: 0.44, blue: 0.50)
        case .settings: Color(red: 0.38, green: 0.40, blue: 0.45)
        }
    }

    /// Slightly deeper shade for pressed / gradient-end states.
    private var accentDeep: Color {
        switch self {
        case .smartScan: Color(red: 0.17, green: 0.34, blue: 0.60)
        case .cleanup: Color(red: 0.12, green: 0.40, blue: 0.27)
        case .protection: Color(red: 0.58, green: 0.23, blue: 0.20)
        case .performance: Color(red: 0.53, green: 0.37, blue: 0.06)
        case .applications: Color(red: 0.35, green: 0.30, blue: 0.53)
        case .files: Color(red: 0.11, green: 0.37, blue: 0.42)
        case .settings: Color(red: 0.30, green: 0.32, blue: 0.37)
        }
    }

    /// Primary-action fill: same hue at both stops (near-flat), so buttons
    /// read as solid system-style controls, not gradient candy.
    public var buttonGradient: LinearGradient {
        LinearGradient(colors: [accentColor, accentDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Kept for call-site compatibility (e.g. progress rings). Now a
    /// near-flat accent gradient rather than a decorative sweep.
    public var gradient: LinearGradient {
        LinearGradient(colors: [accentColor, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Detail-pane background: window colour with a faint section wash
    /// fading down from the top. Adaptive in Light and Dark.
    public var colors: [Color] {
        switch self {
        case .smartScan:
            [Color(light: Color(red: 0.94, green: 0.96, blue: 0.99), dark: Color(red: 0.10, green: 0.12, blue: 0.16)),
             Color(light: Color(red: 0.97, green: 0.98, blue: 0.99), dark: Color(red: 0.11, green: 0.12, blue: 0.14)),
             Color(light: Color(red: 0.98, green: 0.98, blue: 0.99), dark: Color(red: 0.12, green: 0.12, blue: 0.14))]
        case .cleanup:
            [Color(light: Color(red: 0.94, green: 0.98, blue: 0.96), dark: Color(red: 0.09, green: 0.14, blue: 0.12)),
             Color(light: Color(red: 0.97, green: 0.99, blue: 0.98), dark: Color(red: 0.11, green: 0.13, blue: 0.12)),
             Color(light: Color(red: 0.98, green: 0.99, blue: 0.99), dark: Color(red: 0.12, green: 0.12, blue: 0.13))]
        case .protection:
            [Color(light: Color(red: 0.99, green: 0.95, blue: 0.94), dark: Color(red: 0.16, green: 0.11, blue: 0.11)),
             Color(light: Color(red: 0.99, green: 0.97, blue: 0.97), dark: Color(red: 0.13, green: 0.12, blue: 0.12)),
             Color(light: Color(red: 0.99, green: 0.98, blue: 0.98), dark: Color(red: 0.12, green: 0.12, blue: 0.13))]
        case .performance:
            [Color(light: Color(red: 0.99, green: 0.97, blue: 0.92), dark: Color(red: 0.15, green: 0.13, blue: 0.09)),
             Color(light: Color(red: 0.99, green: 0.98, blue: 0.96), dark: Color(red: 0.13, green: 0.12, blue: 0.11)),
             Color(light: Color(red: 0.99, green: 0.99, blue: 0.98), dark: Color(red: 0.12, green: 0.12, blue: 0.13))]
        case .applications:
            [Color(light: Color(red: 0.96, green: 0.95, blue: 0.99), dark: Color(red: 0.12, green: 0.11, blue: 0.16)),
             Color(light: Color(red: 0.98, green: 0.97, blue: 0.99), dark: Color(red: 0.12, green: 0.12, blue: 0.14)),
             Color(light: Color(red: 0.98, green: 0.98, blue: 0.99), dark: Color(red: 0.12, green: 0.12, blue: 0.14))]
        case .files:
            [Color(light: Color(red: 0.93, green: 0.97, blue: 0.98), dark: Color(red: 0.09, green: 0.13, blue: 0.15)),
             Color(light: Color(red: 0.96, green: 0.98, blue: 0.99), dark: Color(red: 0.11, green: 0.12, blue: 0.13)),
             Color(light: Color(red: 0.98, green: 0.99, blue: 0.99), dark: Color(red: 0.12, green: 0.12, blue: 0.13))]
        case .settings:
            [Color(light: Color(red: 0.96, green: 0.97, blue: 0.98), dark: Color(red: 0.13, green: 0.14, blue: 0.16)),
             Color(light: Color(red: 0.97, green: 0.98, blue: 0.99), dark: Color(red: 0.12, green: 0.13, blue: 0.14)),
             Color(light: Color(red: 0.98, green: 0.98, blue: 0.99), dark: Color(red: 0.12, green: 0.12, blue: 0.14))]
        }
    }

    /// Full-pane background gradient built from `colors`.
    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// Detail-pane background for the selected module.
///
/// With "Remove background colors" (Settings) the pane is the plain
/// system window colour; otherwise the theme's faint top wash.
public struct GradientBackgroundView: View {
    let theme: ModuleTheme
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false

    public init(theme: ModuleTheme) {
        self.theme = theme
    }

    public var body: some View {
        if removeBackgroundColors {
            CleanRDesign.windowBackground
        } else {
            theme.backgroundGradient
        }
    }
}
