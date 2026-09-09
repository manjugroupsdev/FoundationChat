import Foundation

// MARK: - GeoTrackConsentManager

/// Manages user consent for GPS time tracking.
///
/// Mirrors Android's SessionManager geoConsentGiven / geoConsentDeclined flags.
/// Consent is stored locally. Tracking transport never writes consent or
/// bootstrap state to the MMS business host.
@MainActor
@Observable
final class GeoTrackConsentManager {

    static let shared = GeoTrackConsentManager()

    // MARK: - UserDefaults keys

    private static let consentGivenKey   = "geotrack.consent.given"
    private static let consentDeclinedKey = "geotrack.consent.declined"

    // MARK: - Dependencies

    private let userDefaults: UserDefaults

    // MARK: - Observable state

    /// True when the user has previously consented to geo tracking.
    private(set) var hasConsented: Bool

    /// True when the user has explicitly declined.
    private(set) var hasDeclined: Bool

    /// True while the consent API call is in flight.
    private(set) var isRecording = false

    // MARK: - Derived

    /// Whether the user needs to see the consent screen.
    var needsConsent: Bool { !hasConsented && !hasDeclined }

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        self.hasConsented = userDefaults.bool(forKey: Self.consentGivenKey)
        self.hasDeclined  = userDefaults.bool(forKey: Self.consentDeclinedKey)
    }

    // MARK: - Actions

    /// Records consent locally before requesting platform permissions.
    func giveConsent() async {
        userDefaults.set(true,  forKey: Self.consentGivenKey)
        userDefaults.set(false, forKey: Self.consentDeclinedKey)
        hasConsented = true
        hasDeclined  = false

        isRecording = true
        defer { isRecording = false }

    }

    /// Records the decline locally with the same behavior as Android.
    func declineConsent() async {
        userDefaults.set(false, forKey: Self.consentGivenKey)
        userDefaults.set(true,  forKey: Self.consentDeclinedKey)
        hasConsented = false
        hasDeclined  = true

        isRecording = true
        defer { isRecording = false }
    }

    /// Clears stored consent so the user is prompted again.
    func resetConsent() {
        userDefaults.removeObject(forKey: Self.consentGivenKey)
        userDefaults.removeObject(forKey: Self.consentDeclinedKey)
        hasConsented = false
        hasDeclined  = false
    }

}
