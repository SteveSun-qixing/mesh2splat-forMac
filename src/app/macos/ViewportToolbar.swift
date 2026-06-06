import SwiftUI

struct ViewportToolbar: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.openImportPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canImport)
            .help(importHelp)

            Button {
                appState.openExportPanel()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(!canExport)
            .help(exportHelp)

            toolbarDivider

            Button {
                appState.refreshRendererStatusFromBridge()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appState.metalView == nil)
            .help("Refresh renderer status")

            Button {
                appState.resetRenderSettings()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .help("Reset render settings")

            toolbarDivider

            Menu {
                Picker("Render Mode", selection: $appState.renderMode) {
                    ForEach(RenderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label("Mode: \(appState.renderMode.title)", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .help("Choose render mode")

            Toggle(isOn: $appState.meshRenderingEnabled) {
                Label("Mesh", systemImage: "cube")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .help("Toggle mesh rendering")

            Toggle(isOn: $appState.gaussianRenderingEnabled) {
                Label("Gaussians", systemImage: "circle.grid.cross")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .help("Toggle gaussian rendering")
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .font(.caption)
        .lineLimit(1)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 20)
    }

    private var canImport: Bool {
        appState.metalView != nil && !isChoosingImportFile && !isExporting
    }

    private var canExport: Bool {
        appState.metalView != nil &&
            appState.importedFileName != nil &&
            hasGaussians &&
            !isConverting &&
            !isExporting
    }

    private var hasGaussians: Bool {
        gaussianCount > 0
    }

    private var gaussianCount: Int {
        Int(appState.gaussianCountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var isChoosingImportFile: Bool {
        appState.importStatus.localizedCaseInsensitiveContains("choosing")
    }

    private var isConverting: Bool {
        appState.rendererRuntimeStatus == "Converting" ||
            appState.conversionStatus.localizedCaseInsensitiveContains("running") ||
            appState.conversionStatus.localizedCaseInsensitiveContains("converting")
    }

    private var isExporting: Bool {
        appState.rendererRuntimeStatus == "Exporting" ||
            appState.exportStatus.localizedCaseInsensitiveContains("choosing") ||
            appState.exportStatus.localizedCaseInsensitiveContains("writing")
    }

    private var importHelp: String {
        if appState.metalView == nil {
            return "Viewport unavailable"
        }

        if isChoosingImportFile {
            return "Choosing file"
        }

        if isExporting {
            return "Export in progress"
        }

        return "Import a mesh"
    }

    private var exportHelp: String {
        if appState.metalView == nil {
            return "Viewport unavailable"
        }

        if appState.importedFileName == nil {
            return "Import a mesh first"
        }

        if isConverting {
            return "Conversion running"
        }

        if !hasGaussians {
            return "No gaussians ready"
        }

        if isExporting {
            return "Export in progress"
        }

        return "Export gaussian PLY"
    }
}
