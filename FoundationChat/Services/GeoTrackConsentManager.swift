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

    /// When this process last saw a decline. In memory on purpose: a relaunch
    /// asks again at once.
    private var lastDeclinedAt: Date?

    /// How long a decline keeps the screen away, so it cannot reopen the
    /// moment the person leaves it.
    static let declineGrace: TimeInterval = 120

    /// Whether the user needs to see the consent screen.
    ///
    /// A decline is honoured for the moment, never for good. It used to be
    /// stored and silence this screen permanently — surviving logout, cleared
    /// only by a reinstall — so a tracked staffer who tapped Decline once
    /// clocked in every day with tracking off. The server shows exactly that
    /// cohort. They are now asked again on the next app open.
    var needsConsent: Bool {
        if hasConsented { return false }
        if let lastDeclinedAt, Date().timeIntervalSince(lastDeclinedAt) < Self.declineGrace {
            return false
        }
        return true
    }

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
        lastDeclinedAt = Date()

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
