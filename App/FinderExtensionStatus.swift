import FinderSync
import Observation

/// Whether the user has enabled Orbit's Finder extension in System Settings.
@MainActor @Observable
final class FinderExtensionStatus {
    private(set) var isEnabled = FIFinderSyncController.isExtensionEnabled

    /// The value can only change while the user is in System Settings,
    /// so re-checking when Orbit becomes active again is enough — no polling.
    func refresh() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }

    func openSystemSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
