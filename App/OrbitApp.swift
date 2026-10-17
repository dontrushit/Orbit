import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Orbit", id: "main") {
            MainView()
        }
        .defaultSize(width: 520, height: 460)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Orbit has nothing to do in the background yet: closing the window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
