import AppKit

/// The standard About panel with a short description of Orbit under the version.
@MainActor
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSAttributedString(
            string: String(localized: "Adds the features macOS is missing.\nWorks locally: no servers, accounts or telemetry."),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
