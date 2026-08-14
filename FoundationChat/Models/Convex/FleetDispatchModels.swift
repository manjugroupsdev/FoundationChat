import Foundation

enum FleetDispatchScope: Equatable, Sendable {
    case agency
    case mms
}

struct FleetDispatchProject: Decodable, Hashable, Sendable {
    let id: String
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct FleetDispatchVehicleReference: Decodable, Hashable, Sendable {
    let id: String
    let vehicleNumber: String?
    let type: String?
    let capacity: Int?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case vehicleNumber, type, capacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        vehicleNumber = try container.decodeIfPresent(String.self, forKey: .vehicleNumber)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
    }
}

struct FleetDispatchTrip: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let scheduledDate: String?
    let scheduledTime: String?
    let pickupAddress: String?
    let pickupLat: Double?
    let pickupLng: Double?
    let pickupGoogleMapsLink: String?
    let pickupTime: String?
    let expectedAttendeeCount: Int?
    let vehiclePreference: String?
    let driverName: String?
    let driverPhone: String?
    let clientName: String?
    let clientPhone: String?
    let lmoName: String?
    let status: String?
    let outcome: String?
    let vehicleId: String?
    let project: FleetDispatchProject?
    let vehicle: FleetDispatchVehicleReference?
    let travelDeskArrivedAt: Int64?
    let travelDeskStartedAt: Int64?
    let travelDeskOnSiteAt: Int64?
    let travelDeskPickedFromSiteAt: Int64?
    let travelDeskEndedAt: Int64?
    let completedOffline: Bool?
    let travelDeskPricingMode: String?
    let travelDeskKmRate: Double?
    let travelDeskPackageAmount: Double?
    let travelDeskStartKm: Double?
    let travelDeskEndKm: Double?
    let travelDeskTotalAmount: Double?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case scheduledDate, scheduledTime, pickupAddress, pickupLat, pickupLng
        case pickupGoogleMapsLink, pickupTime
        case expectedAttendeeCount, vehiclePreference, driverName, driverPhone
        case clientName, clientPhone, lmoName, status, outcome, vehicleId, project, vehicle
        case travelDeskArrivedAt, travelDeskStartedAt, travelDeskOnSiteAt
        case travelDeskPickedFromSiteAt, travelDeskEndedAt, completedOffline
        case travelDeskPricingMode, travelDeskKmRate, travelDeskPackageAmount
        case travelDeskStartKm, travelDeskEndKm, travelDeskTotalAmount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        scheduledTime = try container.decodeIfPresent(String.self, forKey: .scheduledTime)
        pickupAddress = try container.decodeIfPresent(String.self, forKey: .pickupAddress)
        pickupLat = try container.decodeFleetDoubleIfPresent(forKey: .pickupLat)
        pickupLng = try container.decodeFleetDoubleIfPresent(forKey: .pickupLng)
        pickupGoogleMapsLink = try container.decodeIfPresent(String.self, forKey: .pickupGoogleMapsLink)
        pickupTime = try container.decodeIfPresent(String.self, forKey: .pickupTime)
        expectedAttendeeCount = try container.decodeIfPresent(Int.self, forKey: .expectedAttendeeCount)
        vehiclePreference = try container.decodeIfPresent(String.self, forKey: .vehiclePreference)
        driverName = try container.decodeIfPresent(String.self, forKey: .driverName)
        driverPhone = try container.decodeIfPresent(String.self, forKey: .driverPhone)
        clientName = try container.decodeIfPresent(String.self, forKey: .clientName)
        clientPhone = try container.decodeIfPresent(String.self, forKey: .clientPhone)
        lmoName = try container.decodeIfPresent(String.self, forKey: .lmoName)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        vehicleId = try container.decodeIfPresent(String.self, forKey: .vehicleId)
        project = try container.decodeIfPresent(FleetDispatchProject.self, forKey: .project)
        vehicle = try container.decodeIfPresent(FleetDispatchVehicleReference.self, forKey: .vehicle)
        travelDeskArrivedAt = try container.decodeFleetInt64IfPresent(forKey: .travelDeskArrivedAt)
        travelDeskStartedAt = try container.decodeFleetInt64IfPresent(forKey: .travelDeskStartedAt)
        travelDeskOnSiteAt = try container.decodeFleetInt64IfPresent(forKey: .travelDeskOnSiteAt)
        travelDeskPickedFromSiteAt = try container.decodeFleetInt64IfPresent(forKey: .travelDeskPickedFromSiteAt)
        travelDeskEndedAt = try container.decodeFleetInt64IfPresent(forKey: .travelDeskEndedAt)
        completedOffline = try container.decodeIfPresent(Bool.self, forKey: .completedOffline)
        travelDeskPricingMode = try container.decodeIfPresent(String.self, forKey: .travelDeskPricingMode)
        travelDeskKmRate = try container.decodeFleetDoubleIfPresent(forKey: .travelDeskKmRate)
        travelDeskPackageAmount = try container.decodeFleetDoubleIfPresent(forKey: .travelDeskPackageAmount)
        travelDeskStartKm = try container.decodeFleetDoubleIfPresent(forKey: .travelDeskStartKm)
        travelDeskEndKm = try container.decodeFleetDoubleIfPresent(forKey: .travelDeskEndKm)
        travelDeskTotalAmount = try container.decodeFleetDoubleIfPresent(forKey: .travelDeskTotalAmount)
    }

    var isCompleted: Bool {
        status?.localizedCaseInsensitiveCompare("completed") == .orderedSame
    }
}

struct FleetDispatchVehicle: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let vehicleNumber: String?
    let make: String?
    let model: String?
    let modelYear: Int?
    let type: String?
    let capacity: Int?
    let defaultDriverName: String?
    let defaultDriverPhone: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case vehicleNumber, make, model, modelYear, type, capacity, defaultDriverName, defaultDriverPhone, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        vehicleNumber = try container.decodeIfPresent(String.self, forKey: .vehicleNumber)
        make = try container.decodeIfPresent(String.self, forKey: .make)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        modelYear = try container.decodeIfPresent(Int.self, forKey: .modelYear)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
        defaultDriverName = try container.decodeIfPresent(String.self, forKey: .defaultDriverName)
        defaultDriverPhone = try container.decodeIfPresent(String.self, forKey: .defaultDriverPhone)
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }

    var isActive: Bool {
        status?.localizedCaseInsensitiveCompare("inactive") != .orderedSame
    }
}

struct FleetDispatchDriver: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let phone: String?
    let address: String?
    /// Lowercase MMS contract value: "old" or "new" (Android TravelDeskDriver).
    let category: String?
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name, phone, address, category, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Driver"
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
    }

    var isActive: Bool { status.localizedCaseInsensitiveCompare("active") == .orderedSame }
}

struct FleetAllocationDraft: Sendable {
    let vehicleId: String
    let pickupTime: String
    let pricingMode: String
    let driverName: String
    let driverPhone: String
    let amount: Double
}

struct FleetAgencyStaff: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let phone: String
    let whatsapp: String?
    let status: String

    private enum CodingKeys: String, CodingKey { case id = "_id", plainId = "id", name, phone, whatsapp, status }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Staff"
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        whatsapp = try container.decodeIfPresent(String.self, forKey: .whatsapp)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
    }
}

// MARK: - MMS dispatch: external agencies

/// An external travel agency an MMS dispatcher can allot a trip to.
/// Mirrors Android TravelDeskAgency (network/TravelDeskModels.kt).
struct FleetDispatchAgency: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let status: String?
    let mobileNumber: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name, status, mobileNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        mobileNumber = try container.decodeIfPresent(String.self, forKey: .mobileNumber)
    }

    var isActive: Bool {
        status?.localizedCaseInsensitiveCompare("inactive") != .orderedSame
    }
}

struct FleetAgencySettings: Codable, Equatable, Sendable {
    var kmRate: Double
    var packageAmount: Double
    var bettaAmount: Double
    var permitCharge: Double
    var permitTax: Double
    var standingChargeWithAc: Double
    var standingChargeDurationMinutes: Double
    var waitingAllowance: Double
    var cancellationAllowance: Double
    var tollCharge: Double

    static let empty = FleetAgencySettings(
        kmRate: 0, packageAmount: 0, bettaAmount: 0, permitCharge: 0,
        permitTax: 0, standingChargeWithAc: 0, standingChargeDurationMinutes: 0,
        waitingAllowance: 0, cancellationAllowance: 0, tollCharge: 0
    )
}

struct FleetOfflineCompletionDraft: Encodable, Sendable {
    var siteVisitId: String? = nil
    var fleetType: String? = nil
    var vehicleId: String? = nil
    var agencyName: String? = nil
    var packageAmount: Double? = nil
    var kmRate: Double? = nil
    var distanceKm: Double? = nil
    var driverName: String? = nil
    var driverPhone: String? = nil
    var beta: Double? = nil
    var beta2: Double? = nil
    var tollAmount: Double? = nil
    var hillCharge: Double? = nil
    var outstationCharge: Double? = nil
    var permitCharge: Double? = nil
    var permitTax: Double? = nil
    var standingCharge: Double? = nil
    var standingTimeMinutes: Int? = nil
    var standingWithAc: Bool? = nil
    var startKm: Double? = nil
    var endKm: Double? = nil
    var startPhotoIds: [String]? = nil
    var endPhotoIds: [String]? = nil
}

private extension KeyedDecodingContainer {
    func decodeFleetDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try decodeIfPresent(String.self, forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return Double(value)
        }
        return nil
    }

    func decodeFleetInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try decodeIfPresent(String.self, forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return Int64(value)
        }
        return nil
    }
}
// MARK: - Billing: custom charge line

/// A custom charge applied at completion / billing. `unit` is one of
/// km / hour / minute / person / toll / trip (kept for display). Mirrors
/// Android TravelDeskAppliedCharge. Codable because it rides on both the
/// billing request (encode) and the trip payload (decode).
struct FleetAppliedCharge: Codable, Hashable, Sendable {
    let label: String?
    let amount: Double?
    let unit: String?

    init(label: String?, amount: Double?, unit: String?) {
        self.label = label
        self.amount = amount
        self.unit = unit
    }
}

// MARK: - Encodable request drafts
//
// These mirror the Android request data classes (network/TravelDeskModels.kt).
// Field names match the wire keys exactly; optional fields are dropped when nil
// (Swift synthesises encodeIfPresent), which the backend treats as absent.

/// POST api/travel-desk/vehicles/update. `status` carries the active/inactive
/// change — Android folds status-change into this same route (no separate one).
struct FleetVehicleUpdateDraft: Encodable, Sendable {
    let id: String
    var vehicleNumber: String? = nil
    var type: String? = nil
    var capacity: Int? = nil
    var defaultDriverName: String? = nil
    var defaultDriverPhone: String? = nil
    var status: String? = nil
}

/// POST api/travel-desk/trips/finalize-billing.
struct FleetFinalizeBillingDraft: Encodable, Sendable {
    let siteVisitId: String
    let startKm: Double
    let endKm: Double
    var startPhotoIds: [String]? = nil
    var endPhotoIds: [String]? = nil
    var kmRate: Double? = nil
    var packageAmount: Double? = nil
    var beta: Double? = nil
    var beta2: Double? = nil
    var tollAmount: Double? = nil
    var hillCharge: Double? = nil
    var outstationCharge: Double? = nil
    var permitCharge: Double? = nil
    var permitTax: Double? = nil
    var standingCharge: Double? = nil
    var customCharges: [FleetAppliedCharge]? = nil
    var vehicleId: String? = nil
    var driverName: String? = nil
    var driverPhone: String? = nil
}

/// POST api/travel-desk/trips/evidence.
struct FleetEvidenceDraft: Encodable, Sendable {
    let siteVisitId: String
    var startPhotoIds: [String]? = nil
    var startKm: Double? = nil
    var endPhotoIds: [String]? = nil
    var endKm: Double? = nil
}

/// POST api/travel-desk/trips/status-update.
struct FleetStatusUpdateDraft: Encodable, Sendable {
    let siteVisitId: String
    let reasonCode: String
    var reasonText: String? = nil
    var voiceStorageId: String? = nil
    var voiceDurationMs: Int? = nil
    var scheduledDate: String? = nil
    var scheduledTime: String? = nil
}
