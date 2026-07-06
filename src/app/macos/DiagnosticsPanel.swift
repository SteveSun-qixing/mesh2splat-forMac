import SwiftUI

struct DiagnosticsPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Diagnostics", systemImage: "stethoscope")
                .font(.headline)

            GroupBox("Runtime") {
                VStack(alignment: .leading, spacing: 10) {
                    DiagnosticsStatusSummary(
                        title: "Runtime",
                        value: appState.rendererRuntimeStatus,
                        tone: DiagnosticsTone(status: appState.rendererRuntimeStatus)
                    )

                    DiagnosticsStatusSummary(
                        title: "Diagnostic",
                        value: appState.diagnosticStatus,
                        tone: DiagnosticsTone(status: appState.diagnosticStatus)
                    )

                    DiagnosticsStatusRow(
                        title: "Message",
                        status: appState.statusText,
                        systemImage: "text.bubble",
                        detail: appState.drawableStatus
                    )

                    DiagnosticsStatusRow(
                        title: "Gaussians",
                        status: appState.gaussianCountText,
                        systemImage: "circle.grid.cross",
                        detail: "\(appState.gaussianBytesText) resident, \(appState.gaussianSortBytesText) sort"
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Workflow") {
                VStack(alignment: .leading, spacing: 12) {
                    DiagnosticsStatusRow(
                        title: "Import",
                        status: appState.importStatus,
                        systemImage: "square.and.arrow.down"
                    )

                    DiagnosticsStatusRow(
                        title: "Conversion",
                        status: appState.conversionStatus,
                        systemImage: "arrow.triangle.2.circlepath",
                        detail: conversionDiagnosticDetail
                    )

                    ProgressView(value: appState.conversionProgress) {
                        Label("Conversion progress", systemImage: "chart.line.uptrend.xyaxis")
                    } currentValueLabel: {
                        Text(appState.conversionProgressText)
                            .monospacedDigit()
                    }

                    DiagnosticsStatusRow(
                        title: "Export",
                        status: appState.exportStatus,
                        systemImage: "square.and.arrow.up",
                        detail: exportDiagnosticDetail
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Renderer Detail") {
                VStack(alignment: .leading, spacing: 10) {
                    DiagnosticsStatusRow(
                        title: "Backend",
                        status: appState.backendSupportStatus,
                        systemImage: "cpu",
                        detail: appState.backendDeviceName
                    )
                    DiagnosticsStatusRow(
                        title: "Shaders",
                        status: appState.backendShaderStatus,
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        detail: appState.backendPipelineStatus
                    )
                    DiagnosticsStatusRow(
                        title: "Frame Failures",
                        status: frameFailureDiagnosticStatus,
                        systemImage: "exclamationmark.triangle",
                        detail: "\(appState.frameCounterText) frames, \(appState.frameFailureText)"
                    )
                    DiagnosticsStatusRow(
                        title: "Tracked Memory",
                        status: appState.trackedBytesText,
                        systemImage: "memorychip",
                        detail: resourceDiagnosticDetail
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Last Error") {
                DiagnosticsErrorContent(error: appState.lastError)
                    .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
    }

    private var conversionDiagnosticDetail: String {
        "\(appState.conversionCounterText), \(appState.conversionTimingText), \(appState.conversionSamplesText)"
    }

    private var exportDiagnosticDetail: String {
        if let exportedFileName = appState.exportedFileName, !exportedFileName.isEmpty {
            return "Last saved: \(exportedFileName)"
        }

        return appState.canExportGaussians ? "PLY export is available." : "Waiting for converted gaussians."
    }

    private var resourceDiagnosticDetail: String {
        "Scene \(appState.sceneBytesText), pending \(appState.pendingConversionBytesText)"
    }

    private var frameFailureDiagnosticStatus: String {
        appState.frameFailureText.hasPrefix("0 ") ? "No failures" : appState.frameFailureText
    }
}

private struct DiagnosticsStatusSummary: View {
    let title: String
    let value: String
    let tone: DiagnosticsTone

    var body: some View {
        Label {
            LabeledContent(title) {
                Text(value)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        } icon: {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color)
        }
    }
}

private struct DiagnosticsStatusRow: View {
    let title: String
    let status: String
    let systemImage: String
    var detail: String?

    var body: some View {
        Label {
            LabeledContent(title) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
        }
    }

    private var tone: DiagnosticsTone {
        DiagnosticsTone(status: status)
    }
}

private struct DiagnosticsErrorContent: View {
    let error: String?

    var body: some View {
        Label {
            LabeledContent("Error") {
                Text(errorText)
                    .foregroundStyle(error == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == nil ? .green : .red)
        }
    }

    private var errorText: String {
        guard let error, !error.isEmpty else {
            return "No errors"
        }

        return error
    }
}

private struct DiagnosticsTone {
    let symbolName: String
    let color: Color

    init(status: String) {
        let normalizedStatus = status.lowercased()

        if normalizedStatus.contains("failed") ||
            normalizedStatus.contains("error") ||
            normalizedStatus.contains("unsupported") {
            symbolName = "xmark.circle.fill"
            color = .red
        } else if normalizedStatus.contains("warning") ||
            normalizedStatus.contains("unavailable") ||
            normalizedStatus.contains("cancelled") {
            symbolName = "exclamationmark.triangle.fill"
            color = .orange
        } else if normalizedStatus.contains("choosing") ||
            normalizedStatus.contains("running") ||
            normalizedStatus.contains("writing") ||
            normalizedStatus.contains("converting") ||
            normalizedStatus.contains("%") {
            symbolName = "arrow.triangle.2.circlepath.circle.fill"
            color = .blue
        } else if normalizedStatus.contains("ready") ||
            normalizedStatus.contains("loaded") ||
            normalizedStatus.contains("saved") ||
            normalizedStatus.contains("rendering") ||
            normalizedStatus.contains("info") {
            symbolName = "checkmark.circle.fill"
            color = .green
        } else {
            symbolName = "circle.fill"
            color = .secondary
        }
    }
}
