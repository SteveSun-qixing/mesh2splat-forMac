import SwiftUI

struct TelemetryPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        GroupBox("Telemetry") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    StatusPill(
                        title: "Runtime",
                        value: appState.rendererRuntimeStatus,
                        tint: runtimeTint
                    )
                    StatusPill(
                        title: "Diagnostic",
                        value: appState.diagnosticStatus,
                        tint: diagnosticTint
                    )
                }

                ProgressView(value: appState.conversionProgress) {
                    HStack {
                        Text("Conversion")
                        Spacer()
                        Text(appState.conversionProgressText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                    TelemetryMetric(
                        title: "Drawable",
                        value: appState.drawableStatus,
                        systemImage: "rectangle.inset.filled"
                    )
                    TelemetryMetric(
                        title: "Gaussians",
                        value: appState.gaussianCountText,
                        systemImage: "sparkles"
                    )
                    TelemetryMetric(
                        title: "Frames",
                        value: appState.frameCounterText,
                        systemImage: "rectangle.stack"
                    )
                    TelemetryMetric(
                        title: "Timing",
                        value: appState.frameTimingText,
                        systemImage: "timer"
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 96), spacing: 8),
            GridItem(.flexible(minimum: 96), spacing: 8)
        ]
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

    private var diagnosticTint: Color {
        switch appState.diagnosticStatus.lowercased() {
        case "error":
            return .red
        case "warning":
            return .orange
        default:
            return .blue
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct TelemetryMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
