import Foundation

public enum PathFormatter {
    /// The user's real home folder. In the sandboxed extension `NSHomeDirectory()` and
    /// `FileManager.homeDirectoryForCurrentUser` point into its container instead.
    public static var userHomeDirectory: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }

    /// Paths of `urls`, one per line.
    public static func string(for urls: [URL], format: CopyPathSettings.PathFormat, homeDirectory: String) -> String {
        urls.map { path(of: $0, format: format, homeDirectory: homeDirectory) }.joined(separator: "\n")
    }

    static func path(of url: URL, format: CopyPathSettings.PathFormat, homeDirectory: String) -> String {
        let path = url.path
        guard format == .homeRelative else { return path }

        let home = homeDirectory.count > 1 && homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        if path == home { return "~" }
        // Match whole components: "/Users/annabel" isn't inside "/Users/anna".
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
