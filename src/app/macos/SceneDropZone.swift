import AppKit
import SwiftUI

struct SceneDropZone: View {
    @ObservedObject var appState: Mesh2SplatAppState
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .frame(width: 36, height: 36)

            VStack(spacing: 4) {
                Text(dropTitle)
                    .font(.headline)

                Text(dropSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                appState.openImportPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canImport)
            .help(importAvailabilityMessage)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 164)
        .background(dropBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    dropBorderColor,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: URL.self) { urls, _ in
            importFirstSupportedURL(from: urls)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private var canImport: Bool {
        appState.metalView != nil && !isChoosingImportFile && !isExporting
    }

    private var isChoosingImportFile: Bool {
        appState.importStatus.localizedCaseInsensitiveContains("choosing")
    }

    private var isExporting: Bool {
        appState.exportStatus.localizedCaseInsensitiveContains("choosing") ||
            appState.exportStatus.localizedCaseInsensitiveContains("writing") ||
            appState.rendererRuntimeStatus == "Exporting"
    }

    private var dropTitle: String {
        isDropTargeted ? "Release to Import" : "Drop Scene File"
    }

    private var dropSubtitle: String {
        if let importedFileName = appState.importedFileName, !importedFileName.isEmpty {
            return importedFileName
        }

        return "GLB, GLTF, or PLY"
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

    private var dropBackground: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.12)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var dropBorderColor: Color {
        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35)
    }

    private func importFirstSupportedURL(from urls: [URL]) -> Bool {
        guard canImport, let url = urls.first(where: Self.isSupportedSceneURL) else {
            return false
        }

        appState.importMesh(at: url)
        return true
    }

    private static func isSupportedSceneURL(_ url: URL) -> Bool {
        supportedSceneExtensions.contains(url.pathExtension.lowercased())
    }

    private static let supportedSceneExtensions: Set<String> = ["glb", "gltf", "ply"]
}
