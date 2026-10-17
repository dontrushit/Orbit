import Foundation

/// Stable identifier of a module. Persisted in settings, so never rename an existing one.
public struct ModuleID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

/// Background color of a module's icon tile, mapped to a system color by the UI.
public enum ModuleTint: Sendable {
    case blue, green, indigo, orange, pink, purple, red, teal, yellow, gray
}

/// A self-contained feature that the user can switch on or off in Orbit.
public protocol OrbitModule: Sendable {
    var id: ModuleID { get }
    var title: LocalizedStringResource { get }
    var summary: LocalizedStringResource { get }
    /// SF Symbol shown in the module's icon tile.
    var symbolName: String { get }
    var tint: ModuleTint { get }
    var isEnabledByDefault: Bool { get }
}

extension OrbitModule {
    public var isEnabledByDefault: Bool { true }
}
