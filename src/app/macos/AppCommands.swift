import SwiftUI

struct Mesh2SplatCommands: Commands {
    let appState: Mesh2SplatAppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Scene...") {
                appState.openImportPanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Export Gaussian PLY...") {
                appState.openExportPanel()
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandMenu("Renderer") {
            Button("Reset Render Settings") {
                appState.resetRenderSettings()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Refresh Renderer Status") {
                appState.refreshRendererStatusFromBridge()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}
