import AppKit
import SwiftUI

struct ExportWorkflowPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export")
                .font(.headline)

            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Source", value: appState.importedFileName ?? "None")
                    Picker("Format", selection: $appState.exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(appState.exportFormat.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    LabeledContent("Gaussians", value: gaussiansOutputSummary)
                    LabeledContent("Gaussian buffers", value: appState.gaussianBytesText)
                    LabeledContent("Sort workspace", value: appState.gaussianSortBytesText)
                    LabeledContent("Pending memory", value: appState.pendingConversionBytesText)
                    LabeledContent("Conversion jobs", value: appState.conversionCounterText)
                    LabeledContent("Conversion timing", value: appState.conversionTimingText)
                    LabeledContent("Export", value: appState.exportStatus)
                    LabeledContent("Last saved", value: appState.exportedFileName ?? "None")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Workflow") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(workflowItems) { item in
                        ExportWorkflowStepRow(item: item)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Preflight") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(preflightItems) { item in
                        ExportPreflightRow(item: item)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Actions") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        appState.openImportPanel()
                    } label: {
                        Label("Import Scene", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        appState.openExportPanel()
                    } label: {
                        Label("Export PLY", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canExport)
                    .help(exportButtonHelp)
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workflowItems: [ExportWorkflowItem] {
        [
            ExportWorkflowItem(
                title: "Import",
                detail: importDetail,
                state: hasImportedMesh ? .complete : .waiting,
                systemImage: "square.and.arrow.down"
            ),
            ExportWorkflowItem(
                title: "Convert",
                detail: conversionDetail,
                state: conversionStepState,
                systemImage: "wand.and.stars"
            ),
            ExportWorkflowItem(
                title: "Export",
                detail: exportDetail,
                state: exportStepState,
                systemImage: "square.and.arrow.up"
            )
        ]
    }

    private var preflightItems: [ExportPreflightItem] {
        [
            ExportPreflightItem(
                title: "Viewport ready",
                detail: viewportReady ? "Metal viewport is connected." : "Open the Metal viewport before exporting.",
                isSatisfied: viewportReady
            ),
            ExportPreflightItem(
                title: "Scene imported",
                detail: appState.importedFileName ?? "Import a source scene first.",
                isSatisfied: hasImportedMesh
            ),
            ExportPreflightItem(
                title: "Conversion enabled",
                detail: conversionEnabledDetail,
                isSatisfied: appState.conversionEnabled || hasGaussians
            ),
            ExportPreflightItem(
                title: "Conversion finished",
                detail: conversionFinishedDetail,
                isSatisfied: !isConverting
            ),
            ExportPreflightItem(
                title: "Gaussians available",
                detail: gaussiansAvailableDetail,
                isSatisfied: hasGaussians
            ),
            ExportPreflightItem(
                title: "Export idle",
                detail: exportIdleDetail,
                isSatisfied: !isExporting
            ),
            ExportPreflightItem(
                title: "Renderer healthy",
                detail: rendererHealthDetail,
                isSatisfied: !hasRendererError
            )
        ]
    }

    private var canExport: Bool {
        appState.canExportGaussians && preflightItems.allSatisfy(\.isSatisfied)
    }

    private var viewportReady: Bool {
        appState.metalView != nil
    }

    private var hasImportedMesh: Bool {
        guard let importedFileName = appState.importedFileName else { return false }
        return !importedFileName.isEmpty
    }

    private var hasGaussians: Bool {
        appState.gaussianCount > 0
    }

    private var isConverting: Bool {
        appState.rendererRuntimeStatus == "Converting" ||
            appState.conversionStatus.localizedCaseInsensitiveContains("running") ||
            appState.conversionStatus.localizedCaseInsensitiveContains("converting") ||
            appState.conversionStatus.contains("%")
    }

    private var isExporting: Bool {
        appState.rendererRuntimeStatus == "Exporting" ||
            appState.exportStatus.localizedCaseInsensitiveContains("choosing") ||
            appState.exportStatus.localizedCaseInsensitiveContains("writing")
    }

    private var hasRendererError: Bool {
        appState.rendererRuntimeStatus == "Failed" || appState.diagnosticStatus == "Error"
    }

    private var conversionStepState: ExportWorkflowState {
        if hasRendererError {
            return .failed
        }
        if isConverting {
            return .active
        }
        if hasGaussians {
            return .complete
        }
        return hasImportedMesh ? .waiting : .idle
    }

    private var exportStepState: ExportWorkflowState {
        if appState.exportStatus.localizedCaseInsensitiveContains("failed") {
            return .failed
        }
        if isExporting {
            return .active
        }
        if appState.exportStatus.localizedCaseInsensitiveContains("saved") {
            return .complete
        }
        return canExport ? .waiting : .idle
    }

    private var importDetail: String {
        guard let importedFileName = appState.importedFileName, !importedFileName.isEmpty else {
            return "Choose a GLB, GLTF, or Gaussian PLY scene."
        }

        return "\(importedFileName) - \(sceneInventoryDetail)"
    }

    private var conversionDetail: String {
        if isConverting {
            return "\(appState.conversionProgressText), \(appState.conversionCounterText), \(appState.conversionTimingText)"
        }

        if hasGaussians {
            return "\(appState.gaussianCountText) gaussians, \(appState.conversionSamplesText)"
        }

        return appState.conversionStatus
    }

    private var exportDetail: String {
        if let exportedFileName = appState.exportedFileName, !exportedFileName.isEmpty {
            return "\(appState.exportStatus) - \(exportedFileName)"
        }

        if canExport {
            return "Ready to write \(appState.exportFormat.title)."
        }

        return appState.exportStatus
    }

    private var sceneInventoryDetail: String {
        "\(appState.meshCountText) meshes, \(appState.materialCountText) materials, \(appState.textureCountText) textures"
    }

    private var gaussiansOutputSummary: String {
        guard hasGaussians else {
            return "\(appState.gaussianCountText) ready"
        }

        return "\(appState.gaussianCountText) ready, \(appState.gaussianBytesText) resident"
    }

    private var conversionEnabledDetail: String {
        if hasGaussians {
            return "Converted gaussians are already available."
        }
        return appState.conversionEnabled ? "Mesh to splats is enabled." : "Enable mesh to splats before converting."
    }

    private var conversionFinishedDetail: String {
        if isConverting {
            return "Wait for \(appState.conversionProgressText) conversion to finish before exporting."
        }
        return appState.conversionStatus
    }

    private var gaussiansAvailableDetail: String {
        hasGaussians ? "\(appState.gaussianCountText) gaussians ready, \(appState.gaussianBytesText) in buffers." : "No gaussian points are ready yet."
    }

    private var exportIdleDetail: String {
        isExporting ? appState.exportStatus : "No export write is currently active."
    }

    private var rendererHealthDetail: String {
        if hasRendererError {
            return appState.lastError ?? "Resolve the renderer error before exporting."
        }
        return "Runtime \(appState.rendererRuntimeStatus), diagnostic \(appState.diagnosticStatus), backend \(appState.backendSupportStatus)."
    }

    private var exportButtonHelp: String {
        guard let firstBlockingItem = preflightItems.first(where: { !$0.isSatisfied }) else {
            return "Choose a destination for \(appState.exportFormat.title)."
        }
        return firstBlockingItem.detail
    }
}

private struct ExportWorkflowItem: Identifiable {
    let title: String
    let detail: String
    let state: ExportWorkflowState
    let systemImage: String

    var id: String { title }
}

private struct ExportPreflightItem: Identifiable {
    let title: String
    let detail: String
    let isSatisfied: Bool

    var id: String { title }
}

private enum ExportWorkflowState {
    case idle
    case waiting
    case active
    case complete
    case failed

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .waiting: return "Waiting"
        case .active: return "Active"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .waiting: return "clock"
        case .active: return "arrow.triangle.2.circlepath"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .waiting: return .secondary
        case .active: return .accentColor
        case .complete: return .green
        case .failed: return .red
        }
    }
}

private struct ExportWorkflowStepRow: View {
    let item: ExportWorkflowItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                    Spacer(minLength: 8)
                    Label(item.state.title, systemImage: item.state.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(item.state.tint)
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct ExportPreflightRow: View {
    let item: ExportPreflightItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isSatisfied ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(item.isSatisfied ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
