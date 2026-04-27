import CoreMotion
import Foundation

// MARK: - GeoTrackActivityMonitor

/// Wraps CMMotionActivityManager to provide real-time activity classification.
///
/// Maps iOS CMMotionActivity types to the Android-compatible strings used in
/// GeoTrackLocationPoint payloads: STILL, WALKING, ON_BICYCLE, IN_VEHICLE, RUNNING.
///
/// All hardware dependencies are injectable closures for full unit testability.
@MainActor
@Observable
final class GeoTrackActivityMonitor {

    // MARK: - Injected providers

    /// Returns whether motion activity hardware/authorization is available.
    var isAvailableProvider: () -> Bool

    /// Starts hardware updates; injectable for tests.
    var startUpdatesHandler: (@escaping (String, Int) -> Void) -> Void

    /// Stops hardware updates; injectable for tests.
    var stopUpdatesHandler: () -> Void

    // MARK: - Observable state

    private(set) var currentActivity: String = "STILL"
    private(set) var activityConfidence: Int = 50
    private(set) var isRunning = false

    // MARK: - Private

    private var motionManager: CMMotionActivityManager?

    // MARK: - Init (production)

    init() {
        let manager = CMMotionActivityManager()
        self.motionManager = manager

        self.isAvailableProvider = {
            CMMotionActivityManager.isActivityAvailable()
        }

        self.startUpdatesHandler = { [weak manager] callback in
            manager?.startActivityUpdates(to: .main) { activity in
                guard let activity else { return }
                let (label, confidence) = GeoTrackActivityMonitor.classify(activity)
                callback(label, confidence)
            }
        }

        self.stopUpdatesHandler = { [weak manager] in
            manager?.stopActivityUpdates()
        }
    }

    // MARK: - Init (testable)

    init(
        isAvailableProvider: @escaping () -> Bool,
        startUpdatesHandler: @escaping (@escaping (String, Int) -> Void) -> Void,
        stopUpdatesHandler: @escaping () -> Void
    ) {
        self.isAvailableProvider = isAvailableProvider
        self.startUpdatesHandler = startUpdatesHandler
        self.stopUpdatesHandler = stopUpdatesHandler
    }

    // MARK: - Lifecycle

    /// Begin receiving activity updates. Idempotent.
    func start() {
        guard !isRunning, isAvailableProvider() else { return }
        isRunning = true
        startUpdatesHandler { [weak self] label, confidence in
            Task { @MainActor [weak self] in
                self?.currentActivity = label
                self?.activityConfidence = confidence
            }
        }
    }

    /// Stop activity updates. Safe to call multiple times.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopUpdatesHandler()
        currentActivity = "STILL"
        activityConfidence = 50
    }

    // MARK: - Activity classification

    /// Maps a CMMotionActivity to an Android-compatible activity string and confidence (0–100).
    static func classify(_ activity: CMMotionActivity) -> (label: String, confidence: Int) {
        let confidence = confidenceValue(activity.confidence)

        if activity.automotive {
            return ("IN_VEHICLE", confidence)
        }
        if activity.cycling {
            return ("ON_BICYCLE", confidence)
        }
        if activity.running {
            return ("RUNNING", confidence)
        }
        if activity.walking {
            return ("WALKING", confidence)
        }
        if activity.stationary {
            return ("STILL", confidence)
        }
        // Unknown — default to STILL with low confidence
        return ("STILL", 25)
    }

    /// Converts CMMotionActivityConfidence to a percentage (0–100).
    static func confidenceValue(_ confidence: CMMotionActivityConfidence) -> Int {
        switch confidence {
        case .low:    return 25
        case .medium: return 60
        case .high:   return 90
        @unknown default: return 50
        }
    }
}
