import SwiftUI
import CleanRKit

/// Primary scan action: a calm accent disc with a thin progress track
/// around it, not a glowing gradient block. The disc stays the same
/// size in idle and scanning states so the layout never jumps.
public struct ScanButton: View {
    let title: String
    let subtitle: String?
    let theme: ModuleTheme
    let isScanning: Bool
    let progress: Double
    let action: () -> Void

    public init(
        title: String = L10n.tr("扫描", "Scan", "Сканировать"),
        subtitle: String? = nil,
        theme: ModuleTheme = .smartScan,
        isScanning: Bool = false,
        progress: Double = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.isScanning = isScanning
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        if isScanning {
            scanningContent
        } else {
            Button(action: action) {
                idleContent
            }
            .buttonStyle(ScanDiscButtonStyle(accent: theme.accentColor))
            .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }

    private var scanningContent: some View {
        ZStack {
            Circle()
                .stroke(theme.accentColor.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(width: 112, height: 112)
    }
}

private struct ScanDiscButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 112, height: 112)
            .background {
                Circle().fill(accent)
                Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 5)
                    .padding(-5)
            }
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

public struct ScanProgressRing: View {
    let progress: Double
    let phase: String
    let detail: String?
    let theme: ModuleTheme

    public init(progress: Double, phase: String, detail: String? = nil, theme: ModuleTheme = .smartScan) {
        self.progress = progress
        self.phase = phase
        self.detail = detail
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(theme.accentColor.opacity(0.16), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .frame(width: 104, height: 104)

            VStack(spacing: 5) {
                Text(phase)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: phase)

                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
