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
    private let environment = Mesh2SplatAppEnvironment.production
    private let renderPresetStore = RenderPresetStore()

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
    @Published var conversionTimingText = "Submit 0.0 ms / GPU 0.0 ms"
    @Published var conversionCounterText = "0 / 0"
    @Published var conversionSamplesText = "4 samples"
    @Published var frameTimingText = "CPU 0.0 ms / GPU 0.0 ms"
    @Published var frameCounterText = "0 / 0"
    @Published var frameFailureText = "0 failed"
    @Published var backendName = "Metal"
    @Published var backendDeviceName = "Unknown GPU"
    @Published var backendSupportStatus = "Unknown"
    @Published var backendShaderStatus = "Shader library unknown"
    @Published var backendPipelineStatus = "Pipeline cache unknown"
    @Published var frameUniformBytesText = "0 B"
    @Published var sceneBytesText = "0 B"
    @Published var gaussianBytesText = "0 B"
    @Published var gaussianSortBytesText = "0 B"
    @Published var pendingConversionBytesText = "0 B"
    @Published var trackedBytesText = "0 B"
    @Published var meshCountText = "0"
    @Published var materialCountText = "0"
    @Published var textureCountText = "0"
    @Published var rendererCanImportScene = false
    @Published var rendererCanStartConversion = false
    @Published var rendererCanExportGaussians = false
    @Published var rendererHasVisibleMesh = false
    @Published var exportMatchesCurrentConversion = false
    @Published var rendererMeshRenderingEnabled = true
    @Published var rendererGaussianRenderingEnabled = true
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
        case diagnostics = "Diagnostics"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .scene: return "folder"
            case .render: return "slider.horizontal.3"
            case .export: return "square.and.arrow.up"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    init() {
        applyRenderPreset(renderPresetStore.loadOrDefault(), submit: false)
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
        applyRenderPreset(.defaults, submit: false)
        try? renderPresetStore.save(currentRenderPreset)
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
        try? renderPresetStore.save(currentRenderPreset)
    }

    func refreshRendererStatusFromBridge() {
        guard let rendererBridge else { return }

        let status = rendererBridge.rendererStatus()
        applyRendererStatus(status)
    }

    var canImportMesh: Bool {
        rendererCanImportScene &&
            !importStatus.localizedCaseInsensitiveContains("choosing") &&
            !isExporting
    }

    var canExportGaussians: Bool {
        rendererCanExportGaussians &&
            !isConverting &&
            !isExporting
    }

    var gaussianCount: Int {
        Int(gaussianCountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    var resourceTelemetryBridgeResources: [ResourceTelemetryBridgeResource] {
        [
            ResourceTelemetryBridgeResource(
                id: "frame-uniforms",
                title: "Frame Uniforms",
                value: frameUniformBytesText,
                detail: "Per-frame constants",
                systemImage: "rectangle.stack",
                tint: .blue
            ),
            ResourceTelemetryBridgeResource(
                id: "scene",
                title: "Scene",
                value: sceneBytesText,
                detail: "\(meshCountText) meshes, \(materialCountText) materials",
                systemImage: "cube",
                tint: .green
            ),
            ResourceTelemetryBridgeResource(
                id: "gaussians",
                title: "Gaussians",
                value: gaussianBytesText,
                detail: "\(gaussianCountText) splats",
                systemImage: "circle.grid.cross",
                tint: .purple
            ),
            ResourceTelemetryBridgeResource(
                id: "sort",
                title: "Sort",
                value: gaussianSortBytesText,
                detail: sortingEnabled ? "Depth sorting enabled" : "Depth sorting off",
                systemImage: "arrow.up.arrow.down",
                tint: .orange
            ),
            ResourceTelemetryBridgeResource(
                id: "pending-conversion",
                title: "Pending",
                value: pendingConversionBytesText,
                detail: conversionStatus,
                systemImage: "arrow.triangle.2.circlepath",
                tint: isConverting ? .accentColor : .secondary
            ),
            ResourceTelemetryBridgeResource(
                id: "tracked-total",
                title: "Tracked Total",
                value: trackedBytesText,
                detail: "\(textureCountText) textures",
                systemImage: "memorychip",
                tint: .teal
            )
        ]
    }

    private var documentActions: Mesh2SplatDocumentActions {
        Mesh2SplatDocumentActions(
            openScene: { [weak self] url in self?.importMesh(at: url) },
            exportGaussianPly: { [weak self] url in self?.exportGaussians(to: url) },
            cancel: { [weak self] action in self?.documentActionCancelled(action) }
        )
    }

    private var defaultExportFileName: String {
        environment.exportFileName(forImportedFileName: importedFileName)
    }

    private func startRendererStatusLoop() {
        rendererStatusTask?.cancel()
        rendererStatusTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshRendererStatusFromBridge()
                try? await Task.sleep(nanoseconds: Mesh2SplatAppEnvironment.production.polling.rendererStatusNanoseconds)
            }
        }
    }

    private func applyRendererStatus(_ status: M2SRendererStatus) {
        rendererRuntimeStatus = RendererStatusFormatting.runtimeStateTitle(status.runtimeState)
        diagnosticStatus = RendererStatusFormatting.diagnosticSeverityTitle(status.diagnosticSeverity)
        drawableStatus = RendererStatusFormatting.drawableStatus(
            width: status.drawableWidth,
            height: status.drawableHeight,
            backingScale: status.backingScale
        )
        gaussianCountText = RendererStatusFormatting.gaussianCount(UInt64(status.convertedGaussianCount))
        conversionProgress = RendererStatusFormatting.normalizedProgress(status.conversionProgress)
        conversionProgressText = RendererStatusFormatting.progressPercent(conversionProgress)

        statusText = RendererStatusFormatting.rendererStatusText(status.statusText, fallbackRuntimeTitle: rendererRuntimeStatus)

        if !status.loadedSceneName.isEmpty {
            importedFileName = status.loadedSceneName
        } else if !status.loadedScenePath.isEmpty {
            importedFileName = URL(fileURLWithPath: status.loadedScenePath).lastPathComponent
        }

        rendererCanImportScene = status.canImportScene
        rendererCanStartConversion = status.canStartConversion
        rendererCanExportGaussians = status.canExportGaussians
        rendererHasVisibleMesh = status.hasVisibleMesh
        exportMatchesCurrentConversion = status.exportMatchesCurrentConversion
        rendererMeshRenderingEnabled = status.meshRenderingEnabled
        rendererGaussianRenderingEnabled = status.gaussianRenderingEnabled

        if status.exportMatchesCurrentConversion && !status.exportedFilePath.isEmpty {
            exportedFileName = URL(fileURLWithPath: status.exportedFilePath).lastPathComponent
        }

        conversionStatus = RendererStatusFormatting.conversionStatus(
            isConverting: status.isConverting,
            progress: conversionProgress,
            gaussianCountValue: UInt64(status.convertedGaussianCount)
        )
        if status.canExportGaussians && !status.isConverting &&
            (exportStatus == "Export: waiting" || exportStatus == "Export: not ready") {
            exportStatus = "Export: ready"
        } else if status.isConverting {
            exportStatus = "Export: waiting for conversion"
        } else if !status.hasGaussians && status.hasScene {
            exportStatus = "Export: waiting"
        }

        if status.diagnosticSeverity.rawValue >= M2SRendererDiagnosticSeverity.error.rawValue && !status.errorMessage.isEmpty {
            lastError = status.errorMessage
        } else if status.diagnosticSeverity.rawValue < M2SRendererDiagnosticSeverity.error.rawValue {
            lastError = nil
        }

        let frameStats = status.frameStats
        frameTimingText = RendererStatusFormatting.frameTiming(
            cpuMs: frameStats.lastCpuEncodeMs,
            gpuMs: frameStats.lastGpuMs
        )
        frameCounterText = RendererStatusFormatting.frameCounter(
            completed: frameStats.completedFrameCount,
            submitted: frameStats.submittedFrameCount
        )
        frameFailureText = "\(frameStats.failedFrameCount) failed"

        let backendStatus = status.backendStatus
        backendName = backendStatus.backendName.isEmpty ? "Metal" : backendStatus.backendName
        backendDeviceName = backendStatus.deviceName.isEmpty ? "Unknown GPU" : backendStatus.deviceName
        backendSupportStatus = backendStatus.supported ? "Supported" : "Unsupported"
        backendShaderStatus = backendStatus.shaderLibraryReady ? "Shader library ready" : "Shader library unavailable"
        backendPipelineStatus = backendStatus.pipelineCacheReady ? "Pipeline cache ready" : "Pipeline cache unavailable"

        let resourceStats = status.resourceStats
        frameUniformBytesText = RendererStatusFormatting.bytes(resourceStats.frameUniformBytes)
        sceneBytesText = RendererStatusFormatting.bytes(resourceStats.sceneBytes)
        gaussianBytesText = RendererStatusFormatting.bytes(resourceStats.gaussianBytes)
        gaussianSortBytesText = RendererStatusFormatting.bytes(resourceStats.gaussianSortBytes)
        pendingConversionBytesText = RendererStatusFormatting.bytes(resourceStats.pendingConversionBytes)
        trackedBytesText = RendererStatusFormatting.bytes(resourceStats.trackedBytes)
        meshCountText = "\(resourceStats.meshCount)"
        materialCountText = "\(resourceStats.materialCount)"
        textureCountText = "\(resourceStats.textureCount)"

        let conversionStats = status.conversionStats
        conversionSamplesText = "\(conversionStats.samplesPerTriangle) samples"
        conversionCounterText = RendererStatusFormatting.frameCounter(
            completed: conversionStats.completedConversionCount,
            submitted: conversionStats.submittedConversionCount,
            failed: conversionStats.failedConversionCount
        )
        conversionTimingText = RendererStatusFormatting.conversionTiming(
            cpuSubmitMs: conversionStats.lastCpuSubmitMs,
            gpuMs: conversionStats.lastGpuMs
        )
    }

    private var isConverting: Bool {
        rendererRuntimeStatus == "Converting" ||
            conversionStatus.localizedCaseInsensitiveContains("running") ||
            conversionStatus.localizedCaseInsensitiveContains("converting") ||
            conversionStatus.contains("%")
    }

    private var isExporting: Bool {
        rendererRuntimeStatus == "Exporting" ||
            exportStatus.localizedCaseInsensitiveContains("choosing") ||
            exportStatus.localizedCaseInsensitiveContains("writing")
    }

    private var currentRenderPreset: RenderPreset {
        RenderPreset(
            renderMode: renderMode,
            splatSize: splatSize,
            exposure: exposure,
            gamma: gamma,
            backgroundBrightness: backgroundBrightness,
            quality: conversionQuality,
            toggles: RenderPreset.Toggles(
                sortingEnabled: sortingEnabled,
                meshRenderingEnabled: meshRenderingEnabled,
                gaussianRenderingEnabled: gaussianRenderingEnabled,
                conversionEnabled: conversionEnabled
            )
        )
    }

    private func applyRenderPreset(_ preset: RenderPreset, submit: Bool) {
        isResettingRenderSettings = true
        renderMode = preset.renderMode
        splatSize = preset.splatSize
        exposure = preset.exposure
        gamma = preset.gamma
        backgroundBrightness = preset.backgroundBrightness
        conversionQuality = preset.quality
        sortingEnabled = preset.toggles.sortingEnabled
        meshRenderingEnabled = preset.toggles.meshRenderingEnabled
        gaussianRenderingEnabled = preset.toggles.gaussianRenderingEnabled
        conversionEnabled = preset.toggles.conversionEnabled
        isResettingRenderSettings = false

        if submit {
            submitRenderSettings()
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
