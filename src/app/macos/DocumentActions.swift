import AppKit
import UniformTypeIdentifiers

@MainActor
struct Mesh2SplatDocumentActions {
    var openScene: (URL) -> Void
    var exportGaussianPly: (URL) -> Void
    var cancel: (Mesh2SplatAppState.DocumentAction) -> Void

    func importMesh() {
        let panel = NSOpenPanel()
        panel.title = "Import Mesh"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.meshContentTypes

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else {
                    cancel(.importMesh)
                    return
                }
                openScene(url)
            }
        }
    }

    func exportGaussians(defaultName: String) {
        let panel = NSSavePanel()
        panel.title = "Export Gaussian PLY"
        panel.message = "Choose where to save the converted gaussian point cloud."
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = Self.plyContentTypes

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else {
                    cancel(.exportGaussians)
                    return
                }
                exportGaussianPly(url)
            }
        }
    }

    private static var meshContentTypes: [UTType] {
        ["glb", "gltf"].compactMap { UTType(filenameExtension: $0) }
    }

    private static var plyContentTypes: [UTType] {
        UTType(filenameExtension: "ply").map { [$0] } ?? []
    }
}
