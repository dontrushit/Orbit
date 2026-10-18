import Foundation

public enum FileCreator {
    public enum Failure: Error {
        case noAvailableName
    }

    static let maxAttempts = 1000

    /// Creates a file from `template` in `folder` under the first free name —
    /// "Untitled.txt", "Untitled 2.txt", "Untitled 3.txt", … — and returns its URL.
    public static func createFile(from template: FileTemplate, baseName: String, in folder: URL) throws -> URL {
        try write(Data(template.contents.utf8), baseName: baseName, fileExtension: template.fileExtension, in: folder)
    }

    /// Writes `data` to `folder` under the first free name built from `baseName`, never replacing a file.
    static func write(_ data: Data, baseName: String, fileExtension: String, in folder: URL) throws -> URL {
        for index in 1...maxAttempts {
            let url = folder.appendingPathComponent(fileName(baseName: baseName, fileExtension: fileExtension, index: index), isDirectory: false)
            do {
                // Checking for an existing file and writing happen in one step, so there is no race.
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw Failure.noAvailableName
    }

    static func fileName(baseName: String, fileExtension: String, index: Int) -> String {
        index == 1 ? "\(baseName).\(fileExtension)" : "\(baseName) \(index).\(fileExtension)"
    }
}
