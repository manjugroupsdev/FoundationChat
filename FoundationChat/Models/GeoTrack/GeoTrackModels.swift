import Foundation

// MARK: - Base Response

struct GeoTrackBaseResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let status: String?
}

// MARK: - Tracking Bootstrap / Device Sync

struct TrackingDeviceSyncRequest: Encodable, Sendable {
    let deviceId: String
    let platform: String
    let appVersion: String
    let pushToken: String?
    let notificationPermission: Bool
    let fineLocationPermission: Bool
    let backgroundLocationPermission: Bool
    let activityRecognitionPermission: Bool
    let batteryOptimizationIgnored: Bool?
    let manufacturer: String?
    let model: String?

    init(
        deviceId: String,
        platform: String = "ios",
        appVersion: String,
        pushToken: String? = nil,
        notificationPermission: Bool,
        fineLocationPermission: Bool,
        backgroundLocationPermission: Bool,
        activityRecognitionPermission: Bool,
        batteryOptimizationIgnored: Bool? = nil,
        manufacturer: String? = "Apple",
        model: String? = nil
    ) {
        self.deviceId = deviceId
        self.platform = platform
        self.appVersion = appVersion
        self.pushToken = pushToken
        self.notificationPermission = notificationPermission
        self.fineLocationPermission = fineLocationPermission
        self.backgroundLocationPermission = backgroundLocationPermission
        self.activityRecognitionPermission = activityRecognitionPermission
        self.batteryOptimizationIgnored = batteryOptimizationIgnored
        self.manufacturer = manufacturer
        self.model = model
    }
}

struct TrackingBootstrapResponse: Decodable, Sendable {
    let success: Bool
    let data: TrackingBootstrapData?
    let error: String?
}

struct TrackingDeviceSyncResponse: Decodable, Sendable {
    let success: Bool
    let device: TrackingDevice?
    let bootstrap: TrackingBootstrapData?
    let error: String?
}

struct TrackingConsentRecord: Decodable, Sendable {
    let staffId: String?
    let consentVersionKey: String?
    let policyKey: String?
    let status: String?
    let appVersion: String?
    let actedAt: Int64?
    let source: String?
}

struct TrackingAssignmentInfo: Decodable, Sendable {
    let policyKey: String?
    let scopeType: String?
}

struct TrackingAssignments: Decodable, Sendable {
    let attendance: TrackingAssignmentInfo?
    let siteVisit: TrackingAssignmentInfo?
}

struct TrackingPolicy: Decodable, Sendable {
    let key: String?
    let label: String?
    let consentVersionKey: String?
    let requiresConsent: Bool?
    let requiresFineLocation: Bool?
    let requiresBackgroundLocation: Bool?
    let requiresActivityRecognition: Bool?
    let requiresNotificationPermission: Bool?
    let samplingMovingSeconds: Int?
    let samplingStationarySeconds: Int?
    let routeOptimizationEnabled: Bool?
    let routeDeviationThresholdMeters: Int?
}

struct TrackingSession: Decodable, Sendable {
    let id: String?
    let staffId: String?
    let policyKey: String?
    let contextType: String?
    let contextId: String?
    let sessionState: String?
    let deviceId: String?
    let startedAt: Int64?
    let endedAt: Int64?
    let lastHeartbeatAt: Int64?
    let lastLocationAt: Int64?
    let routeExpectedDistanceMeters: Int?
    let routeActualDistanceMeters: Int?
    let routeVarianceMeters: Int?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case staffId, policyKey, contextType, contextId, sessionState, deviceId,
             startedAt, endedAt, lastHeartbeatAt, lastLocationAt,
             routeExpectedDistanceMeters, routeActualDistanceMeters, routeVarianceMeters
    }
}

struct TrackingDevice: Decodable, Sendable {
    let id: String?
    let staffId: String?
    let deviceId: String
    let platform: String?
    let appVersion: String?
    let pushToken: String?
    let notificationPermission: Bool?
    let fineLocationPermission: Bool?
    let backgroundLocationPermission: Bool?
    let activityRecognitionPermission: Bool?
    let status: String?
    let lastSyncedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case staffId, deviceId, platform, appVersion, pushToken,
             notificationPermission, fineLocationPermission,
             backgroundLocationPermission, activityRecognitionPermission,
             status, lastSyncedAt
    }
}

struct ConsentVersionInfo: Decodable, Sendable {
    let key: String
    let title: String?
    let body: String?
    let locale: String?
}

struct TrackingBootstrapData: Decodable, Sendable {
    let staffId: String
    let assignment: TrackingAssignments?
    let consentVersion: ConsentVersionInfo?
    let consent: TrackingConsentRecord?
    let activeSession: TrackingSession?
    let currentPolicy: TrackingPolicy?
    let device: TrackingDevice?
    let shouldTrack: Bool
    let shouldPromptConsent: Bool
}

// MARK: - Location Point (push-batch)

/// Matches the Convex locationPointValidator exactly.
struct GeoTrackLocationPoint: Encodable, Sendable {
    let pointId: String?
    let deviceSequence: Int64?
    let lat: Double
    let lng: Double
    let accuracy: Double
    let speed: Double
    let bearing: Double
    let altitude: Double?
    let activity: String
    let activityConfidence: Int
    let isMock: Bool
    let batteryPct: Int
    let networkType: String
    let gpsEnabled: Bool
    let airplaneMode: Bool
    let recordedAt: Int64  // Unix epoch milliseconds

    init(
        pointId: String? = nil,
        deviceSequence: Int64? = nil,
        lat: Double,
        lng: Double,
        accuracy: Double,
        speed: Double,
        bearing: Double,
        altitude: Double?,
        activity: String,
        activityConfidence: Int,
        isMock: Bool,
        batteryPct: Int,
        networkType: String,
        gpsEnabled: Bool,
        airplaneMode: Bool,
        recordedAt: Int64
    ) {
        self.pointId = pointId
        self.deviceSequence = deviceSequence
        self.lat = lat
        self.lng = lng
        self.accuracy = accuracy
        self.speed = speed
        self.bearing = bearing
        self.altitude = altitude
        self.activity = activity
        self.activityConfidence = activityConfidence
        self.isMock = isMock
        self.batteryPct = batteryPct
        self.networkType = networkType
        self.gpsEnabled = gpsEnabled
        self.airplaneMode = airplaneMode
        self.recordedAt = recordedAt
    }
}

struct GeoTrackPushBatchRequest: Encodable, Sendable {
    let sessionId: String
    let deviceId: String
    let requestId: String
    let points: [GeoTrackLocationPoint]
}

struct GeoTrackPushBatchResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let inserted: Int?
    let insertedCount: Int?
    let duplicateCount: Int?
    let filteredCount: Int?
    let filteredReasons: [String: Int]?
    let tamperDetected: Bool?
}

// MARK: - Start Tracking

struct GeoTrackStartRequest: Encodable, Sendable {
    let lat: Double?
    let lng: Double?

    init(lat: Double? = nil, lng: Double? = nil) {
        self.lat = lat
        self.lng = lng
    }
}

// MARK: - Stop Tracking (no body needed, response is GeoTrackBaseResponse)

struct EmptyGeoTrackRequest: Encodable, Sendable {}

// MARK: - Heartbeat

struct GeoTrackHeartbeatRequest: Encodable, Sendable {
    let sessionId: String?
    let deviceId: String?
    let requestId: String
    let deviceSequence: Int64
    let batteryPct: Int
    let appVersion: String
    let recordedAt: Int64
    let airplaneMode: Bool?
    let locationEnabled: Bool?
}

// MARK: - Tamper

enum GeoTrackTamperEventType: String, Encodable, Sendable {
    case mockLocation = "MOCK_LOCATION"
    case airplaneModeOn = "AIRPLANE_MODE_ON"
    case gpsDisabled = "GPS_DISABLED"
    case heartbeatMissed = "HEARTBEAT_MISSED"
    case teleportation = "TELEPORTATION"
    case permissionDowngrade = "PERMISSION_DOWNGRADE"
    case appForceKilled = "APP_FORCE_KILLED"
    case deviceReboot = "DEVICE_REBOOT"
}

enum GeoTrackTamperSeverity: String, Decodable, Sendable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
}

struct GeoTrackTamperReportRequest: Encodable, Sendable {
    let sessionId: String?
    let eventType: String
    let metadata: [String: String]
    // Original occurrence time (ms epoch) for offline-queued events, so a
    // replayed GPS_DISABLED / DEVICE_REBOOT / AIRPLANE_MODE_ON surfaces in the
    // feed at the moment it HAPPENED rather than when connectivity returned.
    // Mirrors Android `TamperReportRequest.detectedAt`. Synthesized Encodable
    // omits this key when nil (a live report stamps server-side receive time).
    let detectedAt: Int64?
    let requestId: String

    init(
        sessionId: String? = nil,
        eventType: String,
        metadata: [String: String] = [:],
        detectedAt: Int64? = nil,
        requestId: String
    ) {
        self.sessionId = sessionId
        self.eventType = eventType
        self.metadata = metadata
        self.detectedAt = detectedAt
        self.requestId = requestId
    }
}

struct GeoTrackTamperEvent: Decodable, Sendable {
    let staffId: String
    let eventType: String
    let severity: String
    let detectedAt: Double
    let acknowledged: Bool
    let staffName: String?
    let staffPhoto: String?
}

struct GeoTrackTamperFeedResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackTamperEvent]?
}

// MARK: - Consent

struct GeoTrackConsentRequest: Encodable, Sendable {
    let consented: Bool
    let appVersion: String
    let policyKey: String
    let status: String
    let deviceId: String

    init(consented: Bool = true, appVersion: String, deviceId: String) {
        self.consented = consented
        self.appVersion = appVersion
        self.policyKey = "attendance_field"
        self.status = consented ? "granted" : "declined"
        self.deviceId = deviceId
    }
}

struct GeoTrackConsentRecord: Decodable, Sendable {
    let staffId: String?
    let consented: Bool
    let consentedAt: Double?
    let appVersion: String?
}

struct GeoTrackConsentStatusResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: GeoTrackConsentRecord?
}

// MARK: - Timeline

struct GeoTrackTimelinePoint: Decodable, Sendable {
    let staffId: String
    let lat: Double
    let lng: Double
    let accuracy: Double?
    let speed: Double
    let bearing: Double?
    let altitude: Double?
    let activity: String
    let activityConfidence: Int?
    let isMock: Bool?
    let batteryPct: Int?
    let networkType: String?
    let gpsEnabled: Bool?
    let airplaneMode: Bool?
    let movementMode: String?
    let recordedAt: Double
}

struct GeoTrackTimelineResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackTimelinePoint]?
}

struct GeoTrackSessionRouteResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: GeoTrackSessionRouteData?
}

struct GeoTrackSessionRouteData: Decodable, Sendable {
    let timeline: [GeoTrackTimelinePoint]
    let trips: [GeoTrackSessionTrip]
    let stops: [GeoTrackSessionStop]
    let routeStart: Double?
    let routeEnd: Double?
    let distanceMeters: Double?
}

struct GeoTrackSessionTrip: Decodable, Sendable {
    let id: String?
    let staffId: String?
    let startedAt: Double?
    let endedAt: Double?
    let startLat: Double?
    let startLng: Double?
    let endLat: Double?
    let endLng: Double?
    let distanceMeters: Double?
    let durationSeconds: Double?
    let pointCount: Int?
    let onDutyCategory: String?
    let fieldVisitId: String?
    let vehicleType: String?
    let snappedPath: [GeoTrackLatLngPoint]?
    let stops: [GeoTrackSessionStop]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case staffId, startedAt, endedAt, startLat, startLng, endLat, endLng
        case distanceMeters, durationSeconds, pointCount, onDutyCategory, fieldVisitId, vehicleType, snappedPath, stops
    }
}

struct GeoTrackSessionStop: Decodable, Sendable {
    let lat: Double
    let lng: Double
    let arrivedAt: Double
    let departedAt: Double?
    let durationMinutes: Int?
    let address: String?
}

struct GeoTrackLatLngPoint: Decodable, Sendable {
    let lat: Double
    let lng: Double
}

// MARK: - Live Status

struct GeoTrackLiveStatusEntry: Decodable, Sendable {
    let staffId: String
    let lat: Double?
    let lng: Double?
    let speed: Double?
    let activity: String?
    let movementMode: String?
    let batteryPct: Int?
    let isTracking: Bool?
    let hasTamperAlert: Bool?
    let lastSeenAt: Double?
    let staffName: String?
    let staffPhoto: String?
    let designation: String?
    let department: String?
}

struct GeoTrackLiveStatusResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackLiveStatusEntry]?
}

// MARK: - Employee Detail

struct GeoTrackStaffInfo: Decodable, Sendable {
    let id: String
    let name: String?
    let phone: String?
    let photo: String?
    let designation: String?
    let department: String?
    let geoTrackingEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, phone, photo, designation, department, geoTrackingEnabled
    }
}

struct GeoTrackEmployeeDetail: Decodable, Sendable {
    let staff: GeoTrackStaffInfo
    let liveStatus: GeoTrackLiveStatusEntry?
    let recentTamperEvents: [GeoTrackTamperEvent]?
    let consent: GeoTrackConsentRecord?
}

struct GeoTrackEmployeeDetailResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: GeoTrackEmployeeDetail?
}

// MARK: - Trips

struct GeoTrackTrip: Decodable, Sendable {
    let id: String
    let staffId: String
    let startedAt: Double
    let endedAt: Double?
    let distanceMeters: Double
    let durationSeconds: Double
    let stops: [GeoTrackStop]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case staffId, startedAt, endedAt, distanceMeters, durationSeconds, stops
    }
}

struct GeoTrackStop: Decodable, Sendable {
    let lat: Double?
    let lng: Double?
    let arrivedAt: Double?
    let leftAt: Double?
}

struct GeoTrackTripsResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackTrip]?
}

// MARK: - Stats

struct GeoTrackStats: Decodable, Sendable {
    let tripCount: Int
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
    let totalStops: Int
    let tamperEventCount: Int
}

struct GeoTrackStatsResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: GeoTrackStats?
}

// MARK: - Assigned Places

struct GeoTrackAssignedPlace: Decodable, Sendable {
    let id: String
    let name: String
    let address: String?
    let type: String?
    let lat: Double?
    let lng: Double?
    let contactPerson: String?
    let contactPhone: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, address, type, lat, lng, contactPerson, contactPhone
    }
}

struct GeoTrackAssignedPlacesResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackAssignedPlace]?
}

// MARK: - Today Visits

struct GeoTrackTodayVisit: Codable, Sendable {
    let id: String
    let clientPlaceId: String
    let scheduledDate: String
    let status: String
    let mobileStatus: String?
    let reachingRadiusMeters: Int?
    let placeName: String?
    let placeAddress: String?
    let placeType: String?
    let placeLat: Double?
    let placeLng: Double?
    let tripType: String?
    let clientPlaceVisitId: String?
    let leadName: String?
    let leadPhone: String?
    let cpVisit: GeoTrackCPVisitState?
    let scheduledStartTime: String?
    let scheduledEndTime: String?
    let visitCategory: String?
    let travelMode: String?
    let vehiclePreference: String?
    let vehicleAssigned: Bool?
    let creationTime: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case clientPlaceId, scheduledDate, status, mobileStatus, reachingRadiusMeters
        case placeName, placeAddress, placeType, placeLat, placeLng
        case tripType, clientPlaceVisitId, leadName, leadPhone, cpVisit
        case scheduledStartTime, scheduledEndTime
        case visitCategory, travelMode, vehiclePreference, vehicleAssigned
        case creationTime = "_creationTime"
    }
}

struct GeoTrackCPVisitState: Codable, Sendable {
    let clientMet: Bool?
    let clientMetAt: Double?
    let clientNoShowReason: String?
    let outcome: String?
    let postponeReasons: [String]?
    let cpType: String?
}

struct GeoTrackTodayVisitsResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackTodayVisit]?
}

struct GeoTrackMarketingCPVisitsResponse: Decodable, Sendable {
    let success: Bool
    let total: Int?
    let visits: [GeoTrackCPVisitDetail]
    let error: String?
}

struct GeoTrackCPVisitDetail: Decodable, Sendable {
    let id: String?
    let leadId: String?
    let clientId: String?
    let clientPlaceId: String?
    let scheduledDate: String?
    let scheduledTime: String?
    let status: String?
    let clientMet: Bool?
    let clientMetAt: Double?
    let clientNoShowReason: String?
    let outcome: String?
    let postponeReasons: [String]?
    let cpType: String?
    let expectedAttendeeCount: Int?
    let foodPreferences: String?
    let vehiclePreference: String?
    let createdAt: Double?
    let proposedSiteVisit: GeoTrackProposedSiteVisit?
    let attendees: [GeoTrackCPVisitAttendee]?
    let lead: GeoTrackCPVisitLead?
    let client: GeoTrackCPVisitClient?
    let clientPlace: GeoTrackCPVisitPlace?
    let fieldVisit: GeoTrackCPVisitFieldVisit?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case leadId, clientId, clientPlaceId, scheduledDate, scheduledTime, status
        case clientMet, clientMetAt, clientNoShowReason, outcome, postponeReasons
        case cpType, expectedAttendeeCount, foodPreferences, vehiclePreference, createdAt
        case proposedSiteVisit, attendees, lead, client, clientPlace, fieldVisit
    }
}

struct GeoTrackProposedSiteVisit: Decodable, Sendable {
    let projectId: String?
    let scheduledDate: String?
    let scheduledTime: String?
    let inchargeStaffId: String?
    let hodStaffId: String?
    let bdoStaffId: String?
    let avpStaffId: String?
    let gmStaffId: String?
    let seniorManagerStaffId: String?
}

struct GeoTrackCPVisitAttendee: Decodable, Sendable {
    let name: String?
}

struct GeoTrackCPVisitLead: Decodable, Sendable {
    let contactName: String?
    let mobileNumber: String?
    let followUpStatus: String?
    let manualProfile: GeoTrackCPVisitLeadManualProfile?
}

struct GeoTrackCPVisitLeadManualProfile: Decodable, Sendable {
    let clientName: String?
}

struct GeoTrackCPVisitClient: Decodable, Sendable {
    let clientName: String?
    let mobileNumber: String?
}

struct GeoTrackCPVisitPlace: Decodable, Sendable {
    let name: String?
    let address: String?
    let formattedAddress: String?
    let lat: Double?
    let lng: Double?
}

struct GeoTrackCPVisitFieldVisit: Decodable, Sendable {
    let id: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status
    }
}

// MARK: - Place Search / Directions

struct GeoTrackPlaceSuggestion: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
}

struct GeoTrackPlaceSearchResponse: Decodable, Sendable {
    let success: Bool
    let data: [GeoTrackPlaceSuggestion]?
    let error: String?
}

struct GeoTrackRouteRequest: Encodable, Sendable {
    let originLat: Double
    let originLng: Double
    let destLat: Double
    let destLng: Double
}

struct GeoTrackRouteResponse: Decodable, Sendable {
    let success: Bool
    let encodedPolyline: String?
    let distanceMeters: Double?
    let durationSeconds: Double?
    let error: String?
}

struct GeoTrackGeocodeAddressRequest: Encodable, Sendable {
    let address: String
}

struct GeoTrackGeocodeAddressResponse: Decodable, Sendable {
    let success: Bool
    let lat: Double?
    let lng: Double?
    let formattedAddress: String?
    let placeId: String?
    let name: String?
    let error: String?
}

// MARK: - Visit Create

struct GeoTrackCreateVisitRequest: Encodable, Sendable {
    let clientPlaceId: String
    let scheduledDate: String
    let notes: String?

    init(clientPlaceId: String, scheduledDate: String, notes: String? = nil) {
        self.clientPlaceId = clientPlaceId
        self.scheduledDate = scheduledDate
        self.notes = notes
    }
}

struct GeoTrackCreateVisitResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let visitId: String?
}

// MARK: - Visit Start

struct GeoTrackStartVisitRequest: Encodable, Sendable {
    let visitId: String
    let lat: Double?
    let lng: Double?

    init(visitId: String, lat: Double? = nil, lng: Double? = nil) {
        self.visitId = visitId
        self.lat = lat
        self.lng = lng
    }
}

// MARK: - MMS Fleet Driver Trip

struct MmsFleetDriverSiteVisitRequest: Encodable, Sendable {
    let siteVisitId: String
}

struct MmsFleetDriverTripsResponse: Decodable, Sendable {
    let success: Bool
    let trips: [FleetDriverTrip]
    let error: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        trips = (try? container.decode([FleetDriverTrip].self, forKey: .trips)) ?? []
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case success, trips, error
    }
}

struct MmsFleetDriverStartRequest: Encodable, Sendable {
    let siteVisitId: String
    let photoIds: [String]
    let startKm: Double?
}

struct MmsFleetDriverEndRequest: Encodable, Sendable {
    let siteVisitId: String
    let photoIds: [String]
    let endKm: Double?
}

struct MmsFleetDriverActionResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
}

// MARK: - Visit Complete

struct GeoTrackCompleteVisitRequest: Encodable, Sendable {
    let visitId: String
    let lat: Double?
    let lng: Double?
    let remarks: String?
    let arrivalPhotoStorageId: String?
    let clientMet: Bool?
    let outcome: String?
    let outcomeNotes: String?
    let postponeReasons: [String]?
    let followUpDate: String?
    let followUpTime: String?

    init(
        visitId: String,
        lat: Double? = nil,
        lng: Double? = nil,
        remarks: String? = nil,
        arrivalPhotoStorageId: String? = nil,
        clientMet: Bool? = nil,
        outcome: String? = nil,
        outcomeNotes: String? = nil,
        postponeReasons: [String]? = nil,
        followUpDate: String? = nil,
        followUpTime: String? = nil
    ) {
        self.visitId = visitId
        self.lat = lat
        self.lng = lng
        self.remarks = remarks
        self.arrivalPhotoStorageId = arrivalPhotoStorageId
        self.clientMet = clientMet
        self.outcome = outcome
        self.outcomeNotes = outcomeNotes
        self.postponeReasons = postponeReasons
        self.followUpDate = followUpDate
        self.followUpTime = followUpTime
    }
}

// MARK: - Arrival OTP

struct GeoTrackArrivalOtpRequestBody: Encodable, Sendable {
    let visitId: String
    let lat: Double
    let lng: Double
}

struct GeoTrackArrivalOtpRequestResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let contactPhoneMasked: String?
    let distance: Int?
    let radius: Int?
}

struct CpOtpAssistRequest: Encodable, Sendable {
    let clientPlaceVisitId: String
    let lat: Double?
    let lng: Double?
    let remark: String?
}

struct CpOtpAssistResponse: Decodable, Sendable {
    let success: Bool
    let gmName: String?
    let error: String?
}

struct GeoTrackArrivalOtpVerifyBody: Encodable, Sendable {
    let visitId: String
    let otp: String
    let lat: Double?
    let lng: Double?
    // Storage id of the arrival photo we just uploaded. Sending it along with
    // the OTP verify links the photo to the fieldVisit row immediately, instead
    // of waiting for completeVisit at trip-end — the web admin CP detail page was
    // showing "No arrival photo yet" for that whole window. Mirrors Android
    // ArrivalOtpVerifyBody.arrivalPhotoStorageId (GeoTrackApi.kt:919-931).
    // Synthesized Encodable omits this key when nil.
    let arrivalPhotoStorageId: String?

    init(
        visitId: String,
        otp: String,
        lat: Double? = nil,
        lng: Double? = nil,
        arrivalPhotoStorageId: String? = nil
    ) {
        self.visitId = visitId
        self.otp = otp
        self.lat = lat
        self.lng = lng
        self.arrivalPhotoStorageId = arrivalPhotoStorageId
    }
}

struct GeoTrackArrivalOtpVerifyResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let attemptsRemaining: Int?
    let arrivalDistanceFromPlaceMeters: Int?
}

struct GeoTrackArrivalOtpCancelBody: Encodable, Sendable {
    let visitId: String
}
