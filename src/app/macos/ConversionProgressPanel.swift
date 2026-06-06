import SwiftUI

struct ConversionProgressPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progress

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                ConversionProgressMetric(
                    title: "Quality",
                    value: appState.conversionQuality.title,
                    systemImage: "slider.horizontal.3"
                )
                ConversionProgressMetric(
                    title: "Samples",
                    value: "\(appState.conversionQuality.rawValue)/tri",
                    systemImage: "triangle"
                )
                ConversionProgressMetric(
                    title: "Gaussians",
                    value: appState.gaussianCountText,
                    systemImage: "sparkles"
                )
                ConversionProgressMetric(
                    title: "State",
                    value: stateTitle,
                    systemImage: statusTone.symbolName,
                    tint: statusTone.color
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ConversionProgressStatusRow(
                    title: "Conversion",
                    value: appState.conversionStatus,
                    tone: statusTone
                )
                ConversionProgressStatusRow(
                    title: appState.conversionEnabled ? "Start/Stop On" : "Start/Stop Off",
                    value: startStopHint,
                    tone: startStopTone
                )
            }
        }
        .padding(14)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Conversion Progress")
                .font(.headline)

            Spacer(minLength: 12)

            Label(stateTitle, systemImage: statusTone.symbolName)
                .font(.caption)
                .foregroundStyle(statusTone.color)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var progress: some View {
        ProgressView(value: progressValue) {
            HStack {
                Text("Progress")
                Spacer(minLength: 12)
                Text(appState.conversionProgressText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .controlSize(.small)
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 92), spacing: 8),
            GridItem(.flexible(minimum: 92), spacing: 8)
        ]
    }

    private var progressValue: Double {
        min(max(appState.conversionProgress, 0.0), 1.0)
    }

    private var gaussianCount: Int {
        Int(appState.gaussianCountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var hasGaussians: Bool {
        gaussianCount > 0
    }

    private var hasImportedMesh: Bool {
        guard let importedFileName = appState.importedFileName else { return false }
        return !importedFileName.isEmpty
    }

    private var isConverting: Bool {
        appState.rendererRuntimeStatus == "Converting" ||
            appState.conversionStatus.localizedCaseInsensitiveContains("running") ||
            appState.conversionStatus.localizedCaseInsensitiveContains("converting")
    }

    private var hasRendererError: Bool {
        appState.rendererRuntimeStatus == "Failed" ||
            appState.diagnosticStatus == "Error" ||
            appState.conversionStatus.localizedCaseInsensitiveContains("failed")
    }

    private var stateTitle: String {
        if hasRendererError {
            return "Failed"
        }

        if isConverting {
            return "Converting"
        }

        if !appState.conversionEnabled {
            return "Stopped"
        }

        if hasGaussians {
            return "Ready"
        }

        if hasImportedMesh {
            return "Waiting"
        }

        return "Idle"
    }

    private var statusTone: ConversionProgressTone {
        if hasRendererError {
            return .error
        }

        if isConverting {
            return .active
        }

        if hasGaussians {
            return .complete
        }

        if appState.conversionEnabled && hasImportedMesh {
            return .waiting
        }

        return .muted
    }

    private var startStopTone: ConversionProgressTone {
        appState.conversionEnabled ? .complete : .muted
    }

    private var startStopHint: String {
        if hasRendererError {
            return appState.lastError ?? "Resolve the renderer error before restarting."
        }

        if appState.conversionEnabled {
            if isConverting {
                return "Running now; turn conversion off to stop new rebuilds."
            }

            if hasGaussians {
                return "On; quality changes will rebuild gaussians."
            }

            if hasImportedMesh {
                return "On; waiting for the renderer to start."
            }

            return "On; import a mesh to start."
        }

        if hasGaussians {
            return "Off; current gaussians remain available."
        }

        return "Off; enable conversion before importing or rebuilding."
    }
}

private enum ConversionProgressTone {
    case active
    case complete
    case waiting
    case error
    case muted

    var color: Color {
        switch self {
        case .active:
            return .orange
        case .complete:
            return .green
        case .waiting:
            return .blue
        case .error:
            return .red
        case .muted:
            return .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .active:
            return "arrow.triangle.2.circlepath"
        case .complete:
            return "checkmark.circle.fill"
        case .waiting:
            return "clock"
        case .error:
            return "exclamationmark.triangle.fill"
        case .muted:
            return "pause.circle"
        }
    }
}

private struct ConversionProgressMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
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

private struct ConversionProgressStatusRow: View {
    let title: String
    let value: String
    let tone: ConversionProgressTone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color)
                .font(.caption)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
