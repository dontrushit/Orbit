import Foundation

/// A kind of file the New File module can create.
public struct FileTemplate: Identifiable, Sendable {
    /// Filename extension without the dot. Also the stable ID persisted in settings.
    public let id: String
    public let name: LocalizedStringResource
    /// Title of the item when the templates are listed right in the context menu.
    public let menuTitle: LocalizedStringResource
    public let contents: String

    public var fileExtension: String { id }

    public static let plainText = FileTemplate(id: "txt", name: "Plain Text", menuTitle: "New Text File", contents: "")
    public static let markdown = FileTemplate(id: "md", name: "Markdown", menuTitle: "New Markdown File", contents: "")
    public static let json = FileTemplate(id: "json", name: "JSON", menuTitle: "New JSON File", contents: "{}\n")
    public static let html = FileTemplate(id: "html", name: "HTML", menuTitle: "New HTML File", contents: """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title></title>
        </head>
        <body>

        </body>
        </html>

        """)

    /// In the order they appear in the menu.
    public static let builtIn: [FileTemplate] = [.plainText, .markdown, .json, .html]
}
