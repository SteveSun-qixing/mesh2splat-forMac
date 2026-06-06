import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Mesh2SplatAppState: ObservableObject {
    @Published var selectedSection: SidebarSection = .scene
    @Published var statusText = "Ready"
    @Published var importedFileName: String?
    @Published var lastError: String?
    @Published var metalView: NSView?

    enum SidebarSection: String, CaseIterable, Identifiable {
        case scene = "Scene"
        case render = "Render"
        case export = "Export"

        var id: String { rawValue }
    }

    func bindMetalView(_ view: NSView) {
        metalView = view
        statusText = "Metal viewport ready"
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
}
