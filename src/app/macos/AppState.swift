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
        statusText = "Metal viewport ready"
        submitRenderSettings()
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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
