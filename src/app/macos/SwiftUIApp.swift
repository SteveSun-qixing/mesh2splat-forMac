import SwiftUI

@main
struct Mesh2SplatSwiftUIApp: App {
    @StateObject private var appState = Mesh2SplatAppState()

    var body: some Scene {
        WindowGroup("Mesh2Splat Metal") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            Mesh2SplatCommands(appState: appState)
        }
    }
}
