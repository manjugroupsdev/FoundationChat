import Foundation

// MARK: - Base Response

struct GeoTrackBaseResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
}

// MARK: - Location Point (push-batch)

/// Matches the Convex locationPointValidator exactly.
struct GeoTrackLocationPoint: Encodable, Sendable {
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
}

struct GeoTrackPushBatchRequest: Encodable, Sendable {
    let points: [GeoTrackLocationPoint]
}

struct GeoTrackPushBatchResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let inserted: Int?
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

// MARK: - Heartbeat

struct GeoTrackHeartbeatRequest: Encodable, Sendable {
    let batteryPct: Int
    let appVersion: String
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
    let eventType: GeoTrackTamperEventType
    let metadata: [String: String]

    init(eventType: GeoTrackTamperEventType, metadata: [String: String] = [:]) {
        self.eventType = eventType
        self.metadata = metadata
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

    init(consented: Bool = true, appVersion: String) {
        self.consented = consented
        self.appVersion = appVersion
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

struct GeoTrackTodayVisit: Decodable, Sendable {
    let id: String
    let clientPlaceId: String
    let scheduledDate: String
    let status: String
    let placeName: String?
    let placeAddress: String?
    let placeType: String?
    let placeLat: Double?
    let placeLng: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case clientPlaceId, scheduledDate, status, placeName, placeAddress, placeType, placeLat, placeLng
    }
}

struct GeoTrackTodayVisitsResponse: Decodable, Sendable {
    let success: Bool
    let error: String?
    let data: [GeoTrackTodayVisit]?
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

// MARK: - Visit Complete

struct GeoTrackCompleteVisitRequest: Encodable, Sendable {
    let visitId: String
    let lat: Double?
    let lng: Double?
    let remarks: String?

    init(visitId: String, lat: Double? = nil, lng: Double? = nil, remarks: String? = nil) {
        self.visitId = visitId
        self.lat = lat
        self.lng = lng
        self.remarks = remarks
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
    let otpExpiresInSeconds: Int?
    let resendCooldownSeconds: Int?
    let maxResends: Int?
    let attemptsRemaining: Int?
    let distance: Int?
    let radius: Int?
}

struct GeoTrackArrivalOtpVerifyBody: Encodable, Sendable {
    let visitId: String
    let otp: String
    let lat: Double?
    let lng: Double?

    init(visitId: String, otp: String, lat: Double? = nil, lng: Double? = nil) {
        self.visitId = visitId
        self.otp = otp
        self.lat = lat
        self.lng = lng
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
