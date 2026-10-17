/// The single list of modules shipped with Orbit. Order here is the order shown in the UI.
public enum ModuleRegistry {
    public static let all: [any OrbitModule] = [
        NewFileModule(),
    ]

    public static func module(withID id: ModuleID) -> (any OrbitModule)? {
        all.first { $0.id == id }
    }
}
