import SwiftUI

struct ViewportOverlay: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RuntimeBadge(
                    title: "Runtime",
                    value: appState.rendererRuntimeStatus,
                    tint: runtimeTint
                )

                ViewportOverlayMetric(
                    title: "Gaussians",
                    value: appState.gaussianCountText,
                    systemImage: "circle.grid.cross"
                )
            }

            HStack(spacing: 8) {
                ViewportOverlayProgress(
                    value: appState.conversionProgress,
                    valueText: appState.conversionProgressText
                )

                ViewportOverlayMetric(
                    title: "Frame",
                    value: appState.frameTimingText,
                    systemImage: "timer"
                )
            }
        }
        .font(.caption)
        .padding(10)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var runtimeTint: Color {
        switch appState.rendererRuntimeStatus.lowercased() {
        case "failed":
            return .red
        case "loading", "converting", "exporting":
            return .orange
        case "rendering", "ready":
            return .green
        default:
            return .secondary
        }
    }
}

private struct RuntimeBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ViewportOverlayMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ViewportOverlayProgress: View {
    let value: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label("Conversion", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(valueText)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            ProgressView(value: value)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
