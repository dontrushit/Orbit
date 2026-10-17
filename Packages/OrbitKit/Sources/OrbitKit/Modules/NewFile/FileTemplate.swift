import Foundation

/// A kind of file the New File module can create.
public struct FileTemplate: Identifiable, Sendable {
    /// Filename extension without the dot. Also the stable ID persisted in settings.
    public let id: String
    public let name: LocalizedStringResource
    public let contents: String

    public var fileExtension: String { id }

    public static let plainText = FileTemplate(id: "txt", name: "Plain Text", contents: "")
    public static let markdown = FileTemplate(id: "md", name: "Markdown", contents: "")
    public static let json = FileTemplate(id: "json", name: "JSON", contents: "{}\n")
    public static let html = FileTemplate(id: "html", name: "HTML", contents: """
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
