import Foundation
import UniformTypeIdentifiers

struct Mesh2SplatAppEnvironment: Equatable {
    let displayName: String
    let bundleIdentifier: String
    let defaultExportFileName: String
    let supportedImportTypes: [UTType]
    let supportedExportTypes: [UTType]
    let polling: PollingIntervals

    static let production = Mesh2SplatAppEnvironment(
        displayName: "Mesh2Splat Metal",
        bundleIdentifier: "com.mesh2splat.metal",
        defaultExportFileName: "mesh2splat-gaussians.ply",
        supportedImportTypes: Self.contentTypes(forFilenameExtensions: ["glb", "gltf"]),
        supportedExportTypes: Self.contentTypes(forFilenameExtensions: ["ply"]),
        polling: .production
    )

    func exportFileName(forImportedFileName importedFileName: String?) -> String {
        guard let importedFileName, !importedFileName.isEmpty else {
            return defaultExportFileName
        }

        let stem = URL(fileURLWithPath: importedFileName).deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else {
            return defaultExportFileName
        }

        return "\(stem)-gaussians.ply"
    }

    private static func contentTypes(forFilenameExtensions filenameExtensions: [String]) -> [UTType] {
        filenameExtensions.compactMap { UTType(filenameExtension: $0) }
    }
}

extension Mesh2SplatAppEnvironment {
    struct PollingIntervals: Equatable {
        let rendererStatusSeconds: TimeInterval
        let rendererStatusNanoseconds: UInt64

        static let production = PollingIntervals(rendererStatusSeconds: 0.25)

        init(rendererStatusSeconds: TimeInterval) {
            self.rendererStatusSeconds = rendererStatusSeconds
            self.rendererStatusNanoseconds = UInt64(rendererStatusSeconds * 1_000_000_000)
        }
    }
}
