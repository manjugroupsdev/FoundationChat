import Foundation

// MARK: - GeoTrackConsentManager

/// Manages user consent for GPS time tracking.
///
/// Mirrors Android's SessionManager geoConsentGiven / geoConsentDeclined flags.
/// Consent is stored locally in UserDefaults and recorded server-side via the
/// Convex /api/geotrack/consent endpoint.
@MainActor
@Observable
final class GeoTrackConsentManager {

    static let shared = GeoTrackConsentManager()

    // MARK: - UserDefaults keys

    private static let consentGivenKey   = "geotrack.consent.given"
    private static let consentDeclinedKey = "geotrack.consent.declined"

    // MARK: - Dependencies

    private let geoAPI: GeoTrackAPIService
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
        geoAPI: GeoTrackAPIService = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.geoAPI = geoAPI
        self.userDefaults = userDefaults
        self.hasConsented = userDefaults.bool(forKey: Self.consentGivenKey)
        self.hasDeclined  = userDefaults.bool(forKey: Self.consentDeclinedKey)
    }

    // MARK: - Actions

    /// Records consent = true locally and on the server.
    /// The local flag is set immediately; server failure is swallowed (retry on next app launch).
    func giveConsent() async {
        userDefaults.set(true,  forKey: Self.consentGivenKey)
        userDefaults.set(false, forKey: Self.consentDeclinedKey)
        hasConsented = true
        hasDeclined  = false

        isRecording = true
        defer { isRecording = false }

        let appVersion = appVersionString()
        try? await geoAPI.recordConsent(consented: true, appVersion: appVersion)
    }

    /// Records consent = false locally. No server call — mirrors Android behaviour.
    func declineConsent() {
        userDefaults.set(false, forKey: Self.consentGivenKey)
        userDefaults.set(true,  forKey: Self.consentDeclinedKey)
        hasConsented = false
        hasDeclined  = true
    }

    /// Clears stored consent so the user is prompted again.
    func resetConsent() {
        userDefaults.removeObject(forKey: Self.consentGivenKey)
        userDefaults.removeObject(forKey: Self.consentDeclinedKey)
        hasConsented = false
        hasDeclined  = false
    }

    // MARK: - Helpers

    private func appVersionString() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "\(v)-ios"
    }
}
