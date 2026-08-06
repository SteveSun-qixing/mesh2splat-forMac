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

enum ExportFormat: Int, CaseIterable, Identifiable {
    case standard3DGS = 0
    case pbr3DGS = 1
    case compactPBR = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .standard3DGS: return "Standard 3DGS"
        case .pbr3DGS: return "PBR 3DGS"
        case .compactPBR: return "Compact PBR"
        }
    }

    var detail: String {
        switch self {
        case .standard3DGS:
            return "Compatible 3D Gaussian PLY"
        case .pbr3DGS:
            return "Keeps metallic and roughness fields"
        case .compactPBR:
            return "Smaller PBR-oriented PLY"
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
    @Published var shadowBytesText = "0 B"
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
    @Published var backgroundColorRed = 0.03
    @Published var backgroundColorGreen = 0.04
    @Published var backgroundColorBlue = 0.05
    @Published var lightingEnabled = true { didSet { submitRenderSettings() } }
    @Published var shadowsEnabled = false { didSet { submitRenderSettings() } }
    @Published var lightPositionX = 3.0 { didSet { submitRenderSettings() } }
    @Published var lightPositionY = 4.0 { didSet { submitRenderSettings() } }
    @Published var lightPositionZ = 2.5 { didSet { submitRenderSettings() } }
    @Published var lightIntensity = 1.0 { didSet { submitRenderSettings() } }
    @Published var lightColorRed = 1.0 { didSet { submitRenderSettings() } }
    @Published var lightColorGreen = 0.95 { didSet { submitRenderSettings() } }
    @Published var lightColorBlue = 0.85 { didSet { submitRenderSettings() } }
    @Published var conversionQuality: ConversionQuality = .balanced { didSet { submitRenderSettings() } }
    @Published var sortingEnabled = true { didSet { submitRenderSettings() } }
    @Published var depthTestEnabled = true { didSet { submitRenderSettings() } }
    @Published var splitScreenEnabled = false { didSet { submitRenderSettings() } }
    @Published var splitScreenPosition = 0.5 { didSet { submitRenderSettings() } }
    @Published var meshRenderingEnabled = true { didSet { submitRenderSettings() } }
    @Published var gaussianRenderingEnabled = true { didSet { submitRenderSettings() } }
    @Published var conversionEnabled = true { didSet { submitRenderSettings() } }
    @Published var showMeshWireframe = false { didSet { submitRenderSettings() } }
    @Published var showGaussianCenters = false { didSet { submitRenderSettings() } }
    @Published var showSortOrder = false { didSet { submitRenderSettings() } }
    @Published var exportFormat: ExportFormat = .standard3DGS

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

    func buildSplats() {
        guard let rendererBridge else {
            lastError = "Renderer is not ready."
            statusText = "Conversion failed"
            conversionStatus = "Conversion: failed"
            return
        }

        if !conversionEnabled {
            conversionEnabled = true
        }

        conversionStatus = "Conversion: starting"
        statusText = conversionStatus
        let result = rendererBridge.startConversion(withSamplesPerTriangle: UInt32(conversionQuality.rawValue))
        applyRendererStatus(result.status)

        let message = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isAccepted {
            lastError = nil
            if result.status.isConverting {
                conversionStatus = "Conversion: running"
                statusText = message.isEmpty ? conversionStatus : message
            } else if result.status.hasGaussians {
                conversionStatus = RendererStatusFormatting.conversionStatus(
                    isConverting: false,
                    progress: RendererStatusFormatting.normalizedProgress(result.status.conversionProgress),
                    gaussianCountValue: UInt64(result.status.convertedGaussianCount)
                )
                statusText = message.isEmpty ? conversionStatus : message
            } else {
                conversionStatus = message.isEmpty ? "Conversion: waiting" : message
                statusText = conversionStatus
            }
        } else {
            lastError = message.isEmpty ? "Could not start conversion." : message
            statusText = "Conversion failed"
            conversionStatus = "Conversion: failed"
        }

        refreshRendererStatusFromBridge()
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
            if isGaussianPlyScene(url) {
                conversionStatus = "Conversion: ready"
                exportStatus = "Export: ready"
            } else {
                conversionStatus = "Conversion: running"
                exportStatus = "Export: waiting"
            }
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
        let exported = Mesh2SplatExportGaussianPlyFromView(metalView, url, UInt32(exportFormat.rawValue))
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

    var backgroundColor: Color {
        Color(
            red: backgroundColorRed.clamped(to: 0.0...1.0),
            green: backgroundColorGreen.clamped(to: 0.0...1.0),
            blue: backgroundColorBlue.clamped(to: 0.0...1.0)
        )
    }

    func setBackgroundColor(_ color: Color) {
        let resolvedColor = NSColor(color)
        guard let rgb = resolvedColor.usingColorSpace(.deviceRGB) else { return }

        isResettingRenderSettings = true
        backgroundColorRed = Double(rgb.redComponent).clamped(to: 0.0...1.0)
        backgroundColorGreen = Double(rgb.greenComponent).clamped(to: 0.0...1.0)
        backgroundColorBlue = Double(rgb.blueComponent).clamped(to: 0.0...1.0)
        backgroundBrightness = (
            backgroundColorRed * 0.2126 +
            backgroundColorGreen * 0.7152 +
            backgroundColorBlue * 0.0722
        ).clamped(to: 0.0...1.0)
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
            conversionEnabled,
            depthTestEnabled,
            splitScreenEnabled,
            splitScreenPosition.clamped(to: 0.0...1.0),
            lightingEnabled,
            shadowsEnabled,
            lightPositionX.clamped(to: -100.0...100.0),
            lightPositionY.clamped(to: -100.0...100.0),
            lightPositionZ.clamped(to: -100.0...100.0),
            lightIntensity.clamped(to: 0.0...1000.0),
            lightColorRed.clamped(to: 0.0...4.0),
            lightColorGreen.clamped(to: 0.0...4.0),
            lightColorBlue.clamped(to: 0.0...4.0),
            renderDebugFlags
        )
        Mesh2SplatSetBackgroundColorForView(
            metalView,
            backgroundColorRed.clamped(to: 0.0...1.0),
            backgroundColorGreen.clamped(to: 0.0...1.0),
            backgroundColorBlue.clamped(to: 0.0...1.0)
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

    var canBuildSplats: Bool {
        rendererCanStartConversion &&
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
                id: "shadows",
                title: "Shadows",
                value: shadowBytesText,
                detail: shadowsEnabled ? "Shadow map enabled" : "Shadow map off",
                systemImage: "lightbulb",
                tint: .yellow
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

    private func isGaussianPlyScene(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("ply") == .orderedSame
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
        syncRenderSettings(from: status)

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
        shadowBytesText = RendererStatusFormatting.bytes(resourceStats.shadowBytes)
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

    private func syncRenderSettings(from status: M2SRendererStatus) {
        isResettingRenderSettings = true
        renderMode = renderMode(fromViewMode: Int(status.viewMode), gaussianVisualizationMode: Int(status.gaussianVisualizationMode))
        splatSize = Double(status.gaussianScale)
        exposure = Double(status.exposure)
        gamma = Double(status.gamma)
        backgroundBrightness = Double(status.backgroundBrightness)
        lightingEnabled = status.lightingEnabled
        shadowsEnabled = status.shadowsEnabled
        lightPositionX = Double(status.lightPositionX)
        lightPositionY = Double(status.lightPositionY)
        lightPositionZ = Double(status.lightPositionZ)
        lightIntensity = Double(status.lightIntensity)
        lightColorRed = Double(status.lightColorRed)
        lightColorGreen = Double(status.lightColorGreen)
        lightColorBlue = Double(status.lightColorBlue)
        sortingEnabled = status.gaussianSortingEnabled
        depthTestEnabled = status.depthTestEnabled
        splitScreenEnabled = status.splitScreenEnabled
        splitScreenPosition = Double(status.splitScreenPosition)
        meshRenderingEnabled = status.meshRenderingEnabled
        gaussianRenderingEnabled = status.gaussianRenderingEnabled
        conversionEnabled = status.meshToGaussianConversionEnabled
        showMeshWireframe = (status.debugFlags & Self.showMeshWireframeFlag) != 0
        showGaussianCenters = (status.debugFlags & Self.showGaussianCentersFlag) != 0
        showSortOrder = (status.debugFlags & Self.showSortOrderFlag) != 0
        if let quality = ConversionQuality(rawValue: Int(status.conversionSamplesPerTriangle)) {
            conversionQuality = quality
        }
        isResettingRenderSettings = false
    }

    private func renderMode(fromViewMode viewMode: Int, gaussianVisualizationMode: Int) -> RenderMode {
        switch gaussianVisualizationMode {
        case 0: return .albedo
        case 1: return .depth
        case 2: return .normal
        case 3: return .geometry
        case 4: return .overdraw
        case 5: return .pbr
        default:
            if viewMode == 1 {
                return .meshOnly
            }
            if viewMode == 2 {
                return .gaussianOnly
            }
            return .final
        }
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
            backgroundColorRed: backgroundColorRed,
            backgroundColorGreen: backgroundColorGreen,
            backgroundColorBlue: backgroundColorBlue,
            lighting: RenderPreset.Lighting(
                enabled: lightingEnabled,
                positionX: lightPositionX,
                positionY: lightPositionY,
                positionZ: lightPositionZ,
                intensity: lightIntensity,
                colorRed: lightColorRed,
                colorGreen: lightColorGreen,
                colorBlue: lightColorBlue
            ),
            quality: conversionQuality,
            toggles: RenderPreset.Toggles(
                sortingEnabled: sortingEnabled,
                depthTestEnabled: depthTestEnabled,
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
        backgroundColorRed = (preset.backgroundColorRed ?? preset.backgroundBrightness * 0.75).clamped(to: 0.0...1.0)
        backgroundColorGreen = (preset.backgroundColorGreen ?? preset.backgroundBrightness).clamped(to: 0.0...1.0)
        backgroundColorBlue = (preset.backgroundColorBlue ?? preset.backgroundBrightness * 1.25).clamped(to: 0.0...1.0)
        lightingEnabled = preset.lighting.enabled
        lightPositionX = preset.lighting.positionX
        lightPositionY = preset.lighting.positionY
        lightPositionZ = preset.lighting.positionZ
        lightIntensity = preset.lighting.intensity
        lightColorRed = preset.lighting.colorRed
        lightColorGreen = preset.lighting.colorGreen
        lightColorBlue = preset.lighting.colorBlue
        shadowsEnabled = false
        conversionQuality = preset.quality
        sortingEnabled = preset.toggles.sortingEnabled
        depthTestEnabled = preset.toggles.depthTestEnabled
        splitScreenEnabled = false
        splitScreenPosition = 0.5
        meshRenderingEnabled = preset.toggles.meshRenderingEnabled
        gaussianRenderingEnabled = preset.toggles.gaussianRenderingEnabled
        conversionEnabled = preset.toggles.conversionEnabled
        showMeshWireframe = false
        showGaussianCenters = false
        showSortOrder = false
        isResettingRenderSettings = false

        if submit {
            submitRenderSettings()
        }
    }

    private static let showMeshWireframeFlag: UInt32 = 1 << 1
    private static let showGaussianCentersFlag: UInt32 = 1 << 2
    private static let showSortOrderFlag: UInt32 = 1 << 4

    private var renderDebugFlags: UInt32 {
        var flags: UInt32 = 0
        if showMeshWireframe {
            flags |= Self.showMeshWireframeFlag
        }
        if showGaussianCenters {
            flags |= Self.showGaussianCentersFlag
        }
        if showSortOrder {
            flags |= Self.showSortOrderFlag
        }
        return flags
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
