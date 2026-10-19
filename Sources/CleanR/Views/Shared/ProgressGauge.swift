import SwiftUI
import CleanRKit

public struct ProgressGauge: View {
    let progress: Double
    let label: String
    let detail: String?
    let theme: ModuleTheme

    public init(progress: Double, label: String, detail: String? = nil, theme: ModuleTheme = .smartScan) {
        self.progress = progress
        self.label = label
        self.detail = detail
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        theme.accentColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct SizeDisplay: View {
    let size: UInt64
    let label: String

    public init(size: UInt64, label: String = L10n.tr("待清理", "to clean up", "к очистке")) {
        self.size = size
        self.label = label
    }

    public var body: some View {
        let parts = FileSizeFormatter.shortFormat(size)
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.value)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(parts.unit)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
