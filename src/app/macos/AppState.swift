import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum RenderMode: Int, CaseIterable, Identifiable {
    case final = 0
    case meshOnly = 1
    case gaussianOnly = 2
    case albedo = 3
    case depth = 4
    case normal = 5
    case geometry = 6
    case overdraw = 7
    case pbr = 8

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .final: return "Final"
        case .meshOnly: return "Mesh"
        case .gaussianOnly: return "Gaussians"
        case .albedo: return "Albedo"
        case .depth: return "Depth"
        case .normal: return "Normal"
        case .geometry: return "Geometry"
        case .overdraw: return "Overdraw"
        case .pbr: return "PBR"
        }
    }
}

enum ConversionQuality: Int, CaseIterable, Identifiable {
    case low = 1
    case balanced = 4
    case high = 9
    case ultra = 16

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .high: return "High"
        case .ultra: return "Ultra"
        }
    }
}

@MainActor
final class Mesh2SplatAppState: ObservableObject {
    @Published var selectedSection: SidebarSection = .scene
    @Published var statusText = "Ready"
    @Published var importedFileName: String?
    @Published var exportedFileName: String?
    @Published var importStatus = "Import: waiting"
    @Published var conversionStatus = "Conversion: idle"
    @Published var exportStatus = "Export: not ready"
    @Published var lastError: String?
    @Published var metalView: NSView?
    @Published var rendererRuntimeStatus = "Unknown"
    @Published var diagnosticStatus = "Info"
    @Published var drawableStatus = "0x0 @1.0x"
    @Published var gaussianCountText = "0"
    @Published var conversionProgress = 0.0
    @Published var conversionProgressText = "0%"
    @Published var frameTimingText = "CPU 0.0 ms / GPU 0.0 ms"
    @Published var frameCounterText = "0 / 0"
    @Published var renderMode: RenderMode = .final { didSet { submitRenderSettings() } }
    @Published var splatSize = 1.0 { didSet { submitRenderSettings() } }
    @Published var exposure = 1.0 { didSet { submitRenderSettings() } }
    @Published var gamma = 2.2 { didSet { submitRenderSettings() } }
    @Published var backgroundBrightness = 0.04 { didSet { submitRenderSettings() } }
    @Published var conversionQuality: ConversionQuality = .balanced { didSet { submitRenderSettings() } }
    @Published var sortingEnabled = true { didSet { submitRenderSettings() } }
    @Published var meshRenderingEnabled = true { didSet { submitRenderSettings() } }
    @Published var gaussianRenderingEnabled = true { didSet { submitRenderSettings() } }
    @Published var conversionEnabled = true { didSet { submitRenderSettings() } }

    private var isResettingRenderSettings = false
    private var rendererBridge: M2SRendererBridge?
    private var rendererStatusTask: Task<Void, Never>?

    enum DocumentAction {
        case importMesh
        case exportGaussians
    }

    enum SidebarSection: String, CaseIterable, Identifiable {
        case scene = "Scene"
        case render = "Render"
        case export = "Export"

        var id: String { rawValue }
    }

    func bindMetalView(_ view: NSView) {
        metalView = view
        rendererBridge = M2SRendererBridge(metalView: view)
        statusText = "Metal viewport ready"
        submitRenderSettings()
        refreshRendererStatusFromBridge()
        startRendererStatusLoop()
    }

    func openImportPanel() {
        importStatus = "Import: choosing file"
        statusText = importStatus
        documentActions.importMesh()
    }

    func openExportPanel() {
        exportStatus = "Export: choosing destination"
        statusText = exportStatus
        documentActions.exportGaussians(defaultName: defaultExportFileName)
    }

    func importMesh(at url: URL) {
        guard let metalView else {
            lastError = "Viewport is not ready."
            statusText = "Import failed"
            importStatus = "Import: failed"
            return
        }

        let loaded = Mesh2SplatOpenMeshInView(metalView, url)
        if loaded {
            importedFileName = url.lastPathComponent
            lastError = nil
            statusText = "Loaded \(url.lastPathComponent)"
            importStatus = "Import: loaded \(url.lastPathComponent)"
            conversionStatus = "Conversion: running"
            exportStatus = "Export: waiting"
            Mesh2SplatFocusMetalView(metalView)
        } else {
            lastError = "Could not load \(url.lastPathComponent)."
            statusText = "Import failed"
            importStatus = "Import: failed"
        }

        Mesh2SplatRefreshMetalViewStatus(metalView)
        refreshRendererStatusFromBridge()
    }

    func exportGaussians(to url: URL) {
        guard let metalView else {
            lastError = "Viewport is not ready."
            statusText = "Export failed"
            exportStatus = "Export: failed"
            return
        }

        exportStatus = "Export: writing \(url.lastPathComponent)"
        statusText = exportStatus
        let exported = Mesh2SplatExportGaussianPlyFromView(metalView, url)
        if exported {
            exportedFileName = url.lastPathComponent
            lastError = nil
            statusText = "Exported \(url.lastPathComponent)"
            exportStatus = "Export: saved \(url.lastPathComponent)"
        } else {
            lastError = "Could not export \(url.lastPathComponent)."
            statusText = "Export failed"
            exportStatus = "Export: failed"
        }

        Mesh2SplatRefreshMetalViewStatus(metalView)
        refreshRendererStatusFromBridge()
    }

    func documentActionCancelled(_ action: DocumentAction) {
        switch action {
        case .importMesh:
            importStatus = "Import: cancelled"
            statusText = importStatus
        case .exportGaussians:
            exportStatus = "Export: cancelled"
            statusText = exportStatus
        }
    }

    func resetRenderSettings() {
        isResettingRenderSettings = true
        renderMode = .final
        splatSize = 1.0
        exposure = 1.0
        gamma = 2.2
        backgroundBrightness = 0.04
        conversionQuality = .balanced
        sortingEnabled = true
        meshRenderingEnabled = true
        gaussianRenderingEnabled = true
        conversionEnabled = true
        isResettingRenderSettings = false
        submitRenderSettings()
    }

    func submitRenderSettings() {
        guard !isResettingRenderSettings, let metalView else { return }

        Mesh2SplatApplyRenderSettingsToView(
            metalView,
            renderMode.rawValue,
            splatSize.clamped(to: 0.1...8.0),
            exposure.clamped(to: 0.0...16.0),
            gamma.clamped(to: 0.1...4.0),
            backgroundBrightness.clamped(to: 0.0...1.0),
            conversionQuality.rawValue,
            sortingEnabled,
            meshRenderingEnabled,
            gaussianRenderingEnabled,
            conversionEnabled
        )
        Mesh2SplatRefreshMetalViewStatus(metalView)
        refreshRendererStatusFromBridge()
    }

    func refreshRendererStatusFromBridge() {
        guard let rendererBridge else { return }

        let status = rendererBridge.rendererStatus()
        applyRendererStatus(status)
    }

    private var documentActions: Mesh2SplatDocumentActions {
        Mesh2SplatDocumentActions(
            openScene: { [weak self] url in self?.importMesh(at: url) },
            exportGaussianPly: { [weak self] url in self?.exportGaussians(to: url) },
            cancel: { [weak self] action in self?.documentActionCancelled(action) }
        )
    }

    private var defaultExportFileName: String {
        guard let importedFileName, !importedFileName.isEmpty else {
            return "mesh2splat-gaussians.ply"
        }

        let stem = URL(fileURLWithPath: importedFileName).deletingPathExtension().lastPathComponent
        return "\(stem)-gaussians.ply"
    }

    private func startRendererStatusLoop() {
        rendererStatusTask?.cancel()
        rendererStatusTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshRendererStatusFromBridge()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func applyRendererStatus(_ status: M2SRendererStatus) {
        rendererRuntimeStatus = runtimeStateTitle(status.runtimeState)
        diagnosticStatus = diagnosticSeverityTitle(status.diagnosticSeverity)
        drawableStatus = "\(status.drawableWidth)x\(status.drawableHeight) @\(String(format: "%.1f", status.backingScale))x"
        gaussianCountText = "\(status.convertedGaussianCount)"
        conversionProgress = Double(status.conversionProgress).clamped(to: 0.0...1.0)
        conversionProgressText = "\(Int((conversionProgress * 100.0).rounded()))%"

        if !status.statusText.isEmpty {
            statusText = status.statusText
        } else {
            statusText = rendererRuntimeStatus
        }

        if !status.loadedScenePath.isEmpty {
            importedFileName = URL(fileURLWithPath: status.loadedScenePath).lastPathComponent
        }

        conversionStatus = status.isConverting ?
            "Conversion: \(conversionProgressText)" :
            "Conversion: \(status.convertedGaussianCount) gaussians"
        if status.hasGaussians && !status.isConverting && exportStatus == "Export: waiting" {
            exportStatus = "Export: ready"
        }

        if status.diagnosticSeverity.rawValue >= M2SRendererDiagnosticSeverity.error.rawValue && !status.errorMessage.isEmpty {
            lastError = status.errorMessage
        } else if status.diagnosticSeverity.rawValue < M2SRendererDiagnosticSeverity.error.rawValue {
            lastError = nil
        }

        let frameStats = status.frameStats
        frameTimingText = "CPU \(String(format: "%.1f", frameStats.lastCpuEncodeMs)) ms / GPU \(String(format: "%.1f", frameStats.lastGpuMs)) ms"
        frameCounterText = "\(frameStats.completedFrameCount) / \(frameStats.submittedFrameCount)"
    }

    private func runtimeStateTitle(_ state: M2SRendererRuntimeState) -> String {
        switch state.rawValue {
        case M2SRendererRuntimeState.ready.rawValue: return "Ready"
        case M2SRendererRuntimeState.loading.rawValue: return "Loading"
        case M2SRendererRuntimeState.converting.rawValue: return "Converting"
        case M2SRendererRuntimeState.rendering.rawValue: return "Rendering"
        case M2SRendererRuntimeState.failed.rawValue: return "Failed"
        case M2SRendererRuntimeState.exporting.rawValue: return "Exporting"
        default: return "Unknown"
        }
    }

    private func diagnosticSeverityTitle(_ severity: M2SRendererDiagnosticSeverity) -> String {
        switch severity.rawValue {
        case M2SRendererDiagnosticSeverity.warning.rawValue: return "Warning"
        case M2SRendererDiagnosticSeverity.error.rawValue: return "Error"
        default: return "Info"
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
