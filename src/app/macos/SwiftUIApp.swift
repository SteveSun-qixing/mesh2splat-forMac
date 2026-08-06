import SwiftUI

@main
struct Mesh2SplatSwiftUIApp: App {
    @NSApplicationDelegateAdaptor(Mesh2SplatAppDelegate.self) private var appDelegate
    @StateObject private var appState = Mesh2SplatAppState()

    var body: some Scene {
        WindowGroup("Mesh2Splat Metal") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 600)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    Mesh2SplatAppDelegate.handleOpenURL(url)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            Mesh2SplatCommands(appState: appState)
        }
    }
}
