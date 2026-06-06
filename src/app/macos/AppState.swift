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
        let panel = NSOpenPanel()
        panel.title = "Import Mesh"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .init(filenameExtension: "glb"),
            .init(filenameExtension: "gltf")
        ].compactMap { $0 }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.importMesh(at: url)
            }
        }
    }

    func importMesh(at url: URL) {
        guard let metalView else {
            lastError = "Viewport is not ready."
            statusText = "Import failed"
            return
        }

        let loaded = Mesh2SplatOpenMeshInView(metalView, url as NSURL)
        if loaded {
            importedFileName = url.lastPathComponent
            lastError = nil
            statusText = "Loaded \(url.lastPathComponent)"
            Mesh2SplatFocusMetalView(metalView)
        } else {
            lastError = "Could not load \(url.lastPathComponent)."
            statusText = "Import failed"
        }

        Mesh2SplatRefreshMetalViewStatus(metalView)
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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
