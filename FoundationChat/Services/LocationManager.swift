import CoreLocation
import Foundation
import UIKit

@MainActor
@Observable
final class LocationTracker: NSObject {
    private let locationManager = CLLocationManager()
    private var pendingWaypoints: [[String: Any]] = []
    private var uploadTask: Task<Void, Never>?

    private static let pendingWaypointsKey = "pendingGPSWaypoints"
    private static let batchSize = 10
    private static let uploadInterval: TimeInterval = 30
    private static let foregroundDistanceFilter: CLLocationDistance = 30
    private static let backgroundDistanceFilter: CLLocationDistance = 100
    private static let minimumPointInterval: TimeInterval = 10
    private var lastRecordedDate: Date?

    // Active trip state
    private(set) var activeSessionId: Int?
    private(set) var activeRefNo: String?
    private(set) var tripStartTime: Date?
    private(set) var isTracking = false
    private(set) var waypointCount = 0

    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var isTripActive: Bool { activeSessionId != nil }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = Self.foregroundDistanceFilter
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .automotiveNavigation
        loadPendingWaypoints()
    }

    // MARK: - Trip Lifecycle

    func startTrip(purpose: String, remarks: String = "") async throws {
        guard !isTripActive else { return }

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
            throw NSError(domain: "LocationTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location permission required. Please try again."])
        }
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            throw NSError(domain: "LocationTracker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Location access denied. Enable in Settings."])
        }

        // Get current location for session start
        locationManager.startUpdatingLocation()
        // Wait briefly for a location fix
        try? await Task.sleep(for: .seconds(2))

        let lat = lastLocation?.coordinate.latitude ?? 0
        let lng = lastLocation?.coordinate.longitude ?? 0

        let api = HRAPIService.shared
        let result = try await api.startGPSSession(
            userId: api.mmsUserId,
            purpose: purpose,
            remarks: remarks,
            startingLatitude: lat,
            startingLongitude: lng
        )

        activeSessionId = result.siteVisitGPSId
        activeRefNo = result.refNo
        tripStartTime = Date()
        waypointCount = 0
        isTracking = true

        // Enable background tracking only when trip is active
        // Guard against crash if background mode not configured in Info.plist
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        locationManager.startMonitoringSignificantLocationChanges()
        startPeriodicUpload()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    func endTrip(remarks: String = "") async throws -> GPSSessionEndResult {
        guard let sessionId = activeSessionId else {
            throw NSError(domain: "LocationTracker", code: 3, userInfo: [NSLocalizedDescriptionKey: "No active trip"])
        }

        // Flush remaining waypoints
        await flushWaypoints()

        let lat = lastLocation?.coordinate.latitude ?? 0
        let lng = lastLocation?.coordinate.longitude ?? 0

        let api = HRAPIService.shared
        let result = try await api.endGPSSession(
            siteVisitGPSId: sessionId,
            userId: api.mmsUserId,
            endingLatitude: lat,
            endingLongitude: lng,
            closingRemarks: remarks
        )

        stopTracking()
        return result
    }

    func cancelTrip() {
        stopTracking()
    }

    func capturePhoto(imageData: Data) async throws -> GPSPhotoUploadResult {
        guard let sessionId = activeSessionId else {
            throw NSError(domain: "LocationTracker", code: 3, userInfo: [NSLocalizedDescriptionKey: "No active trip"])
        }

        let base64 = imageData.base64EncodedString()
        return try await HRAPIService.shared.uploadGPSPhoto(
            siteVisitGPSId: sessionId,
            imageBase64: base64
        )
    }

    func markLocation(description: String) {
        guard isTripActive, let location = lastLocation else { return }
        let wp = buildWaypoint(location: location, isManual: true, description: description)
        pendingWaypoints.append(wp)
        saveWaypoints()
    }

    // MARK: - Private

    private func stopTracking() {
        isTracking = false
        activeSessionId = nil
        activeRefNo = nil
        tripStartTime = nil
        waypointCount = 0
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        }
        uploadTask?.cancel()
        uploadTask = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidEnterBackground() {
        guard isTracking else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = Self.backgroundDistanceFilter
    }

    @objc private func appWillEnterForeground() {
        guard isTracking else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = Self.foregroundDistanceFilter
    }

    private func startPeriodicUpload() {
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.uploadInterval))
                guard !Task.isCancelled else { break }
                await self?.flushWaypoints()
            }
        }
    }

    private func addLocationPoint(_ location: CLLocation) {
        lastLocation = location
        guard isTripActive else { return }

        if let lastDate = lastRecordedDate,
           location.timestamp.timeIntervalSince(lastDate) < Self.minimumPointInterval {
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 150 else { return }

        lastRecordedDate = location.timestamp
        let wp = buildWaypoint(location: location, isManual: false, description: "")
        pendingWaypoints.append(wp)
        waypointCount += 1
        saveWaypoints()

        if pendingWaypoints.count >= Self.batchSize {
            Task { await flushWaypoints() }
        }
    }

    private func buildWaypoint(location: CLLocation, isManual: Bool, description: String) -> [String: Any] {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = device.batteryLevel
        let batteryPct = batteryLevel >= 0 ? Int(batteryLevel * 100) : -1

        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "isManuallyCaptured": isManual,
            "description": description,
            "batteryPercentage": batteryPct,
            "isGPSOn": CLLocationManager.locationServicesEnabled(),
            "isWifiOn": true,
            "signalStrength": 4,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "locationName": "",
        ]
    }

    private func flushWaypoints() async {
        guard !pendingWaypoints.isEmpty, let sessionId = activeSessionId else { return }
        let api = HRAPIService.shared
        let toSend = pendingWaypoints
        pendingWaypoints = []
        saveWaypoints()

        do {
            _ = try await api.postGPSWaypoints(
                siteVisitGPSId: sessionId,
                userId: api.mmsUserId,
                waypoints: toSend
            )
        } catch {
            // Re-queue on failure
            pendingWaypoints.insert(contentsOf: toSend, at: 0)
            saveWaypoints()
        }
    }

    private func saveWaypoints() {
        if let data = try? JSONSerialization.data(withJSONObject: pendingWaypoints) {
            UserDefaults.standard.set(data, forKey: Self.pendingWaypointsKey)
        }
    }

    private func loadPendingWaypoints() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingWaypointsKey),
              let points = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        pendingWaypoints = points
    }
}

extension LocationTracker: @preconcurrency CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            addLocationPoint(location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
