import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    ViewportSurface()
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                    ActiveInspectorPanel(appState: appState)
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                }

                StatusBarView(appState: appState)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mesh2Splat")
                .font(.headline)

            VStack(spacing: 8) {
                Button {
                    appState.openImportPanel()
                } label: {
                    Label("Import Mesh", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.canImportMesh)

                Button {
                    appState.openExportPanel()
                } label: {
                    Label("Export PLY", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!appState.canExportGaussians)
            }
            .controlSize(.large)

            VStack(spacing: 4) {
                ForEach(Mesh2SplatAppState.SidebarSection.allCases) { section in
                    Button {
                        appState.selectedSection = section
                    } label: {
                        HStack(spacing: 8) {
                            Label(section.rawValue, systemImage: section.systemImage)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(section == appState.selectedSection ? Color.accentColor.opacity(0.16) : Color.clear)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 150, idealHeight: 190)

            Divider()

            SidebarSummary(appState: appState)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 220)
    }
}

private struct SidebarSummary: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricBadge("Runtime", value: appState.rendererRuntimeStatus, tone: runtimeTone)
            MetricBadge("Gaussians", value: appState.gaussianCountText, tone: .accent)
            MetricBadge("Memory", value: appState.trackedBytesText, tone: .neutral)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Conversion")
                    Spacer()
                    Text(appState.conversionProgressText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                ProgressView(value: appState.conversionProgress)
                    .controlSize(.small)
            }
        }
    }

    private var runtimeTone: MetricTone {
        switch appState.rendererRuntimeStatus.lowercased() {
        case "failed":
            return .danger
        case "loading", "converting", "exporting":
            return .warning
        case "ready", "rendering":
            return .success
        default:
            return .neutral
        }
    }
}

private struct ViewportSurface: View {
    var body: some View {
        ZStack {
            MetalViewport()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .black))

            VStack(spacing: 0) {
                ViewportToolbarHost()
                Spacer(minLength: 0)
            }

            ViewportOverlayHost()
        }
    }
}

private struct ViewportToolbarHost: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        ViewportToolbar(appState: appState)
    }
}

private struct ViewportOverlayHost: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        ViewportOverlay(appState: appState)
    }
}

private struct ActiveInspectorPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        ScrollView {
            switch appState.selectedSection {
            case .scene:
                VStack(alignment: .leading, spacing: 14) {
                    SceneDropZone(appState: appState)
                    SceneWorkflowPanel(appState: appState)
                }
            case .render:
                VStack(alignment: .leading, spacing: 14) {
                    RenderControlsPanel(appState: appState)
                    ConversionProgressPanel(appState: appState)
                    TelemetryPanel(appState: appState)
                }
            case .export:
                ExportWorkflowPanel(appState: appState)
            case .diagnostics:
                VStack(alignment: .leading, spacing: 14) {
                    DiagnosticsPanel(appState: appState)
                    ResourceTelemetryPanel(
                        appState: appState,
                        bridgeResources: appState.resourceTelemetryBridgeResources
                    )
                    BackendStatusPanel(appState: appState)
                }
            }
        }
        .background(.bar)
    }
}

private struct BackendStatusPanel: View {
    @ObservedObject var appState: Mesh2SplatAppState

    var body: some View {
        GroupBox("Backend") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Name", value: appState.backendName)
                LabeledContent("Device", value: appState.backendDeviceName)
                LabeledContent("Support", value: appState.backendSupportStatus)
                LabeledContent("Shaders", value: appState.backendShaderStatus)
                LabeledContent("Pipelines", value: appState.backendPipelineStatus)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

private struct MetalViewport: NSViewRepresentable {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    func makeNSView(context: Context) -> NSView {
        let view = Mesh2SplatCreateMetalView(NSRect(x: 0, y: 0, width: 960, height: 640))
        DispatchQueue.main.async {
            appState.bindMetalView(view)
            Mesh2SplatFocusMetalView(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Mesh2SplatRefreshMetalViewStatus(nsView)
    }
}
