import AppKit

@MainActor
final class Mesh2SplatAppDelegate: NSObject, NSApplicationDelegate {
    static weak var appState: Mesh2SplatAppState?
    static var pendingOpenURL: URL?

    static func handleOpenURL(_ url: URL) {
        if let appState = appState, let metalView = appState.metalView {
            _ = Mesh2SplatOpenMeshInView(metalView, url)
        } else {
            pendingOpenURL = url
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            Mesh2SplatAppDelegate.handleOpenURL(URL(fileURLWithPath: path))
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
