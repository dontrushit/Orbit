import Foundation
import os

public enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "dev.orbit.mac"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
