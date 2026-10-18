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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Orbit") {
                    AboutPanel.show()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // A settings window should open compact: restoring the last state brings back a window
    // that was once zoomed to the full screen height. `.restorationBehavior(.disabled)` needs macOS 15.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    // Orbit has nothing to do in the background yet: closing the window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
