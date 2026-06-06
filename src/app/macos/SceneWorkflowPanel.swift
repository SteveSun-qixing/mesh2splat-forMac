import SwiftUI

struct SceneWorkflowPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scene Workflow")
                .font(.headline)

            GroupBox("Files") {
                VStack(alignment: .leading, spacing: 8) {
                    WorkflowValueRow(
                        title: "Input",
                        value: appState.importedFileName ?? "No mesh",
                        symbolName: "doc"
                    )

                    WorkflowValueRow(
                        title: "Output",
                        value: appState.exportedFileName ?? "No export",
                        symbolName: "shippingbox"
                    )

                    WorkflowValueRow(
                        title: "Gaussians",
                        value: appState.gaussianCountText,
                        symbolName: "circle.grid.cross"
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Pipeline") {
                VStack(alignment: .leading, spacing: 12) {
                    WorkflowStatusRow(title: "Import", status: appState.importStatus)
                    WorkflowStatusRow(title: "Conversion", status: appState.conversionStatus)

                    if showsConversionProgress {
                        ProgressView(value: appState.conversionProgress) {
                            Text("Progress")
                        } currentValueLabel: {
                            Text(appState.conversionProgressText)
                                .monospacedDigit()
                        }
                    }

                    WorkflowStatusRow(title: "Export", status: appState.exportStatus)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Availability") {
                VStack(alignment: .leading, spacing: 8) {
                    WorkflowAvailabilityRow(
                        title: "Import",
                        message: importAvailabilityMessage,
                        isAvailable: canImport
                    )

                    WorkflowAvailabilityRow(
                        title: "Export",
                        message: exportAvailabilityMessage,
                        isAvailable: canExport
                    )
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    appState.openImportPanel()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canImport)
                .help(importAvailabilityMessage)

                Button {
                    appState.openExportPanel()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!canExport)
                .help(exportAvailabilityMessage)
            }
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
    }

    private var canImport: Bool {
        appState.metalView != nil && !isChoosingImportFile && !isExporting
    }

    private var canExport: Bool {
        appState.metalView != nil &&
            appState.importedFileName != nil &&
            hasGaussians &&
            !isConverting &&
            !isExporting
    }

    private var hasGaussians: Bool {
        (Int(appState.gaussianCountText) ?? 0) > 0
    }

    private var showsConversionProgress: Bool {
        isConverting || appState.conversionProgress > 0.0
    }

    private var isChoosingImportFile: Bool {
        appState.importStatus.lowercased().contains("choosing")
    }

    private var isConverting: Bool {
        appState.conversionStatus.lowercased().contains("running") ||
            appState.rendererRuntimeStatus == "Converting"
    }

    private var isExporting: Bool {
        appState.exportStatus.lowercased().contains("choosing") ||
            appState.exportStatus.lowercased().contains("writing") ||
            appState.rendererRuntimeStatus == "Exporting"
    }

    private var importAvailabilityMessage: String {
        if appState.metalView == nil {
            return "Viewport unavailable"
        }

        if isChoosingImportFile {
            return "Choosing file"
        }

        if isExporting {
            return "Export in progress"
        }

        return "Ready"
    }

    private var exportAvailabilityMessage: String {
        if appState.metalView == nil {
            return "Viewport unavailable"
        }

        if isExporting {
            return "Export in progress"
        }

        if isConverting {
            return "Conversion running"
        }

        if appState.importedFileName == nil {
            return "No mesh imported"
        }

        if !hasGaussians {
            return "No gaussians ready"
        }

        return "Ready"
    }
}

private struct WorkflowValueRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbolName)
                .labelStyle(.titleAndIcon)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct WorkflowStatusRow: View {
    let title: String
    let status: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: tone.symbolName)
                .foregroundStyle(tone.color)
                .font(.caption)
                .frame(width: 14)

            Text(title)

            Spacer(minLength: 12)

            Text(status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var tone: WorkflowStatusTone {
        WorkflowStatusTone(status: status)
    }
}

private struct WorkflowAvailabilityRow: View {
    let title: String
    let message: String
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isAvailable ? .green : .secondary)
                .font(.caption)
                .frame(width: 14)

            Text(title)

            Spacer(minLength: 12)

            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct WorkflowStatusTone {
    let symbolName: String
    let color: Color

    init(status: String) {
        let normalizedStatus = status.lowercased()

        if normalizedStatus.contains("failed") || normalizedStatus.contains("error") {
            symbolName = "xmark.circle.fill"
            color = .red
        } else if normalizedStatus.contains("choosing") ||
            normalizedStatus.contains("running") ||
            normalizedStatus.contains("writing") ||
            normalizedStatus.contains("%") {
            symbolName = "arrow.triangle.2.circlepath.circle.fill"
            color = .blue
        } else if normalizedStatus.contains("loaded") ||
            normalizedStatus.contains("ready") ||
            normalizedStatus.contains("saved") {
            symbolName = "checkmark.circle.fill"
            color = .green
        } else {
            symbolName = "circle.fill"
            color = .secondary
        }
    }
}
