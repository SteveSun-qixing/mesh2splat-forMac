import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            VStack(spacing: 0) {
                MetalViewport()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .black))
                StatusBar()
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                appState.openImportPanel()
            } label: {
                Label("Import Mesh", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Picker("Workspace", selection: $appState.selectedSection) {
                ForEach(Mesh2SplatAppState.SidebarSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            GroupBox("Asset") {
                LabeledContent("Input", value: appState.importedFileName ?? "None")
                LabeledContent("State", value: appState.statusText)
            }

            GroupBox("Render") {
                LabeledContent("Viewport", value: "Metal")
                LabeledContent("Mode", value: "Combined")
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 220)
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

private struct StatusBar: View {
    @EnvironmentObject private var appState: Mesh2SplatAppState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.statusText)
                .lineLimit(1)

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()
            Text("Renderer status")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }
}
