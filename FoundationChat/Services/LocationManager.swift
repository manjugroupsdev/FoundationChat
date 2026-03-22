import CoreLocation
import Foundation
import UIKit

@MainActor
@Observable
final class LocationTracker: NSObject {
    private let locationManager = CLLocationManager()
    private var authStore: AuthStore?
    private var pendingPoints: [[String: Any]] = []
    private var uploadTask: Task<Void, Never>?
    private(set) var isTracking = false

    private static let pendingPointsKey = "pendingLocationPoints"
    private static let batchSize = 10
    private static let uploadInterval: TimeInterval = 120 // 2 minutes

    // Minimum distance (meters) before a new point is recorded.
    // Prevents storing duplicate points when the user is stationary.
    private static let foregroundDistanceFilter: CLLocationDistance = 30
    private static let backgroundDistanceFilter: CLLocationDistance = 100

    // Minimum time (seconds) between stored points to avoid flooding the DB.
    private static let minimumPointInterval: TimeInterval = 15
    private var lastRecordedDate: Date?

    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self

        // NearestTenMeters is accurate enough for route tracking
        // and uses Wi-Fi/cell in addition to GPS — much lighter on battery.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

        // Only fire updates when the user moves at least this far.
        locationManager.distanceFilter = Self.foregroundDistanceFilter

        // Let iOS pause updates when the user is stationary — big battery saver.
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .automotiveNavigation // best for field staff driving/walking routes

        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        loadPendingPoints()
    }

    func startTracking(authStore: AuthStore) {
        self.authStore = authStore
        guard !isTracking else { return }

        let status = locationManager.authorizationStatus
        authorizationStatus = status

        switch status {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginLocationUpdates()
        default:
            break
        }

        // Adjust accuracy based on app state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        uploadTask?.cancel()
        uploadTask = nil
        flushPendingPoints()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App Lifecycle

    @objc private func appDidEnterBackground() {
        guard isTracking else { return }
        // In background: widen distance filter and lower accuracy to save battery.
        // significantLocationChanges keeps running for free (cell tower based).
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = Self.backgroundDistanceFilter
    }

    @objc private func appWillEnterForeground() {
        guard isTracking else { return }
        // In foreground: restore tighter tracking.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = Self.foregroundDistanceFilter
    }

    // MARK: - Private

    private func beginLocationUpdates() {
        isTracking = true
        // significantLocationChanges is almost free on battery — uses cell towers.
        // It wakes the app in background even if iOS suspended it.
        locationManager.startMonitoringSignificantLocationChanges()
        // Standard updates give finer resolution when the app is active.
        locationManager.startUpdatingLocation()
        startPeriodicUpload()
    }

    private func startPeriodicUpload() {
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.uploadInterval))
                guard !Task.isCancelled else { break }
                await self?.flushPendingPoints()
            }
        }
    }

    private func addLocationPoint(_ location: CLLocation) {
        lastLocation = location

        // Throttle: skip if too soon since last recorded point
        if let lastDate = lastRecordedDate,
           location.timestamp.timeIntervalSince(lastDate) < Self.minimumPointInterval
        {
            return
        }
        lastRecordedDate = location.timestamp

        let point: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "speed": max(0, location.speed),
            "heading": location.course >= 0 ? location.course : 0,
            "recordedAt": location.timestamp.timeIntervalSince1970 * 1000,
        ]
        pendingPoints.append(point)
        savePendingPoints()

        if pendingPoints.count >= Self.batchSize {
            Task { await flushPendingPoints() }
        }
    }

    private func flushPendingPoints() {
        guard !pendingPoints.isEmpty, let authStore else { return }
        let pointsToSend = pendingPoints
        pendingPoints = []
        savePendingPoints()

        Task {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: pointsToSend)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                try await authStore.recordLocationBatch(points: jsonString)
            } catch {
                // Put points back on failure — they'll be retried next cycle
                await MainActor.run {
                    self.pendingPoints.insert(contentsOf: pointsToSend, at: 0)
                    self.savePendingPoints()
                }
            }
        }
    }

    private func savePendingPoints() {
        if let data = try? JSONSerialization.data(withJSONObject: pendingPoints) {
            UserDefaults.standard.set(data, forKey: Self.pendingPointsKey)
        }
    }

    private func loadPendingPoints() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingPointsKey),
              let points = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        pendingPoints = points
    }
}

extension LocationTracker: @preconcurrency CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Filter out inaccurate readings (> 150m is noise)
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 150 else { return }
        Task { @MainActor in
            addLocationPoint(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if (status == .authorizedAlways || status == .authorizedWhenInUse), authStore != nil {
                beginLocationUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Will retry on next update cycle
    }
}
