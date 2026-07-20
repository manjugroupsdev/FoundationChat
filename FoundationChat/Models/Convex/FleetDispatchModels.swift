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
    let pickupTime: String?
    let expectedAttendeeCount: Int?
    let vehiclePreference: String?
    let driverName: String?
    let driverPhone: String?
    let status: String?
    let vehicleId: String?
    let project: FleetDispatchProject?
    let vehicle: FleetDispatchVehicleReference?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case scheduledDate, scheduledTime, pickupAddress, pickupTime
        case expectedAttendeeCount, vehiclePreference, driverName, driverPhone
        case status, vehicleId, project, vehicle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        scheduledTime = try container.decodeIfPresent(String.self, forKey: .scheduledTime)
        pickupAddress = try container.decodeIfPresent(String.self, forKey: .pickupAddress)
        pickupTime = try container.decodeIfPresent(String.self, forKey: .pickupTime)
        expectedAttendeeCount = try container.decodeIfPresent(Int.self, forKey: .expectedAttendeeCount)
        vehiclePreference = try container.decodeIfPresent(String.self, forKey: .vehiclePreference)
        driverName = try container.decodeIfPresent(String.self, forKey: .driverName)
        driverPhone = try container.decodeIfPresent(String.self, forKey: .driverPhone)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        vehicleId = try container.decodeIfPresent(String.self, forKey: .vehicleId)
        project = try container.decodeIfPresent(FleetDispatchProject.self, forKey: .project)
        vehicle = try container.decodeIfPresent(FleetDispatchVehicleReference.self, forKey: .vehicle)
    }

    var isCompleted: Bool {
        status?.localizedCaseInsensitiveCompare("completed") == .orderedSame
    }
}

struct FleetDispatchVehicle: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let vehicleNumber: String?
    let type: String?
    let capacity: Int?
    let defaultDriverName: String?
    let defaultDriverPhone: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case vehicleNumber, type, capacity, defaultDriverName, defaultDriverPhone, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        vehicleNumber = try container.decodeIfPresent(String.self, forKey: .vehicleNumber)
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
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name, phone, address, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainId)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Driver"
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        address = try container.decodeIfPresent(String.self, forKey: .address)
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
