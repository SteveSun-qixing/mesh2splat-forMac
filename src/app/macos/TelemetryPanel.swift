import SwiftUI

struct TelemetryPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        GroupBox("Telemetry") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        StatusPill(
                            title: "Runtime",
                            value: appState.rendererRuntimeStatus,
                            detail: appState.statusText,
                            tint: runtimeTint
                        )
                        StatusPill(
                            title: "Diagnostic",
                            value: appState.diagnosticStatus,
                            detail: diagnosticDetail,
                            tint: diagnosticTint
                        )
                    }

                    HStack(alignment: .center, spacing: 8) {
                        StatusPill(
                            title: "Backend",
                            value: appState.backendSupportStatus,
                            detail: backendDetail,
                            tint: backendTint
                        )
                        StatusPill(
                            title: "Export",
                            value: exportReadiness,
                            detail: appState.exportStatus,
                            tint: exportTint
                        )
                    }
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
                        detail: appState.backendDeviceName,
                        systemImage: "rectangle.inset.filled"
                    )
                    TelemetryMetric(
                        title: "Gaussians",
                        value: appState.gaussianCountText,
                        detail: gaussianResourceDetail,
                        systemImage: "sparkles"
                    )
                    TelemetryMetric(
                        title: "Frames",
                        value: appState.frameCounterText,
                        detail: appState.frameFailureText,
                        systemImage: "rectangle.stack"
                    )
                    TelemetryMetric(
                        title: "Timing",
                        value: appState.frameTimingText,
                        detail: "Last CPU / GPU frame",
                        systemImage: "timer"
                    )
                    TelemetryMetric(
                        title: "Conversion Jobs",
                        value: appState.conversionCounterText,
                        detail: conversionDetail,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    TelemetryMetric(
                        title: "Tracked Memory",
                        value: appState.trackedBytesText,
                        detail: trackedResourceDetail,
                        systemImage: "memorychip"
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

    private var diagnosticDetail: String {
        if let lastError = appState.lastError, !lastError.isEmpty {
            return lastError
        }

        return "No blocking renderer error"
    }

    private var backendDetail: String {
        "\(appState.backendShaderStatus), \(appState.backendPipelineStatus)"
    }

    private var exportReadiness: String {
        appState.canExportGaussians ? "Ready" : "Waiting"
    }

    private var gaussianResourceDetail: String {
        "\(appState.gaussianBytesText) buffers, \(appState.gaussianSortBytesText) sort"
    }

    private var conversionDetail: String {
        "\(appState.conversionSamplesText), \(appState.conversionTimingText)"
    }

    private var trackedResourceDetail: String {
        "Scene \(appState.sceneBytesText), pending \(appState.pendingConversionBytesText)"
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

    private var backendTint: Color {
        if appState.backendSupportStatus == "Unsupported" {
            return .red
        }

        if appState.backendShaderStatus.localizedCaseInsensitiveContains("unavailable") ||
            appState.backendPipelineStatus.localizedCaseInsensitiveContains("unavailable") {
            return .orange
        }

        return .green
    }

    private var exportTint: Color {
        if appState.exportStatus.localizedCaseInsensitiveContains("failed") {
            return .red
        }

        if appState.exportStatus.localizedCaseInsensitiveContains("choosing") ||
            appState.exportStatus.localizedCaseInsensitiveContains("writing") {
            return .orange
        }

        return appState.canExportGaussians ? .green : .secondary
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    var detail: String?
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

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct TelemetryMetric: View {
    let title: String
    let value: String
    var detail: String?
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

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
