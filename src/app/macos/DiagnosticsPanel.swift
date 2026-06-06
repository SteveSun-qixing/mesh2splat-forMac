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
                        systemImage: "arrow.triangle.2.circlepath"
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
                        systemImage: "square.and.arrow.up"
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

    var body: some View {
        Label {
            LabeledContent(title) {
                Text(status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            normalizedStatus.contains("error") {
            symbolName = "xmark.circle.fill"
            color = .red
        } else if normalizedStatus.contains("warning") {
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
