import OrbitKit
import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Orbit", id: AppDelegate.mainWindowID) {
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowID = "main"

    private let logger = Log.logger("App")
    private var didFinishLaunching = false

    // A settings window should open compact: restoring the last state brings back a window
    // that was once zoomed to the full screen height. `.restorationBehavior(.disabled)` needs macOS 15.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    // PDF files from the Finder extension (PDF Tools). When they launch Orbit, this comes before
    // applicationDidFinishLaunching, and SwiftUI has already ordered the main window in, but it isn't on screen yet.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let request = PDFToolsRequest(urls: urls) else {
            logger.error("Opened without PDF files")
            return
        }
        // The PDF window first: with no window left, Orbit would quit after the main one goes away.
        PDFToolsWindowController.show(request)
        if !didFinishLaunching {
            // `.defaultLaunchBehavior(.suppressed)` needs macOS 15. Hidden rather than closed, so the Dock icon
            // can bring it back with its state.
            mainWindow?.orderOut(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
    }

    // The Dock icon always brings up the main window, also while a PDF window is open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard let mainWindow else { return true }
        mainWindow.makeKeyAndOrderFront(nil)
        return false
    }

    // Orbit has nothing to do in the background yet: closing the last window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(Self.mainWindowID) == true }
    }
}
