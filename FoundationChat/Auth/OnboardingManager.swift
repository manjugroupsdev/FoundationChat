import Foundation

@Observable
final class OnboardingManager {
    private let defaults = UserDefaults.standard
    private let key = "mconnect_onboarding_completed"
    /// Set alongside the marker file. A restored backup or device transfer
    /// brings this back without the file (excluded from backup), which is how
    /// a new install tells it never played the intro (Android OnboardingPrefs).
    private let markerStampKey = "mconnect_onboarding_marker_written"

    var isOnboardingCompleted: Bool {
        get {
            guard defaults.bool(forKey: key) else { return false }
            if FileManager.default.fileExists(atPath: Self.markerURL.path) { return true }
            if defaults.bool(forKey: markerStampKey) { return false }
            // ponytail: an install updated in place from a build without the
            // marker keeps skipping and is stamped now; a restore of a backup
            // made before this build looks the same and also skips.
            writeMarker()
            return true
        }
        set {
            defaults.set(newValue, forKey: key)
            if newValue { writeMarker() }
        }
    }

    var shouldShowOnboarding: Bool { !isOnboardingCompleted }

    private static var markerURL: URL {
        URL.applicationSupportDirectory.appending(path: "onboarding_completed.marker")
    }

    private func writeMarker() {
        var url = Self.markerURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? Data().write(to: url)) != nil else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        defaults.set(true, forKey: markerStampKey)
    }
}
