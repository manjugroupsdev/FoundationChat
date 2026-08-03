import Foundation

enum FleetDispatchAPIError: LocalizedError {
    case badURL
    case unauthorized
    case server(statusCode: Int, message: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid fleet server URL."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case let .server(statusCode, message):
            if statusCode == 404 {
                return "Fleet dispatch isn't available on this server yet."
            }
            if statusCode == 403 {
                return "You don't have fleet permissions (marketing.fleet.view)."
            }
            return message
        case let .decoding(error):
            return "Fleet data couldn't be read: \(error.localizedDescription)"
        }
    }
}

enum FleetDispatchAPIService {
    private static let baseURL = AppConfig.baseURL
    private static let convexURL = "https://convex-mfpl.theairix.com"

    private struct ListResponse<Item: Decodable>: Decodable {
        let success: Bool
        let data: [Item]?
        let trips: [Item]?
        let vehicles: [Item]?
        let drivers: [Item]?
        let staff: [Item]?
        let error: String?

        var rows: [Item] { trips ?? vehicles ?? drivers ?? staff ?? data ?? [] }
    }

    private struct MutationResponse: Decodable {
        let success: Bool
        let error: String?
    }

    private struct ConvexMutationEnvelope<Arguments: Encodable>: Encodable {
        let path: String
        let args: Arguments
        let format = "json"
    }

    private struct ConvexMutationResponse: Decodable {
        let status: String
        let errorMessage: String?
    }

    private struct AllocateRequest: Encodable {
        let siteVisitId: String
        let vehicleId: String
        let pickupTime: String
        let pricingMode: String
        let driverName: String
        let driverPhone: String
        let kmRate: Double?
        let packageAmount: Double?
    }

    private struct DriverCreateRequest: Encodable {
        let name: String
        let phone: String
        let address: String?
    }

    private struct MMSDriverCreateRequest: Encodable {
        let actingStaffId: String
        let name: String
        let phone: String
        let address: String?
    }

    private struct DriverUpdateRequest: Encodable {
        let id: String
        let name: String?
        let phone: String?
        let address: String?
    }

    private struct MMSDriverUpdateRequest: Encodable {
        let actingStaffId: String
        let id: String
        let name: String?
        let phone: String?
        let address: String?
    }

    private struct DriverStatusRequest: Encodable {
        let id: String
        let status: String
    }

    private struct TripRequest: Encodable { let siteVisitId: String }

    private struct CompleteOfflineRequest: Encodable {
        let siteVisitId: String
        let fleetType: String?
        let vehicleId: String?
        let agencyName: String?
        let packageAmount: Double?
        let kmRate: Double?
        let distanceKm: Double?
        let driverName: String?
        let driverPhone: String?
        let beta: Double?
        let beta2: Double?
        let tollAmount: Double?
        let hillCharge: Double?
        let outstationCharge: Double?
        let permitCharge: Double?
        let permitTax: Double?
        let standingCharge: Double?
        let standingTimeMinutes: Int?
        let standingWithAc: Bool?
        let startKm: Double?
        let endKm: Double?
    }

    private struct AgencyStaffRequest: Encodable {
        let id: String?
        let name: String?
        let phone: String?
        let whatsapp: String?
        let status: String?
    }

    private struct SettingsResponse: Decodable {
        let success: Bool
        let settings: FleetAgencySettings?
        let error: String?
    }

    private struct StorageResponse: Decodable {
        let success: Bool
        let storageId: String?
        let error: String?
    }

    private struct MMSDriverStatusRequest: Encodable {
        let actingStaffId: String
        let id: String
        let status: String
    }

    private struct VehicleCreateRequest: Encodable {
        let vehicleNumber: String
        let type: String?
        let capacity: Int?
        let defaultDriverName: String?
        let defaultDriverPhone: String?
    }

    private struct MMSVehicleCreateRequest: Encodable {
        let actingStaffId: String
        let vehicleNumber: String
        let type: String?
        let capacity: Int?
        let defaultDriverName: String?
        let defaultDriverPhone: String?
    }

    static func listPending(token: String, scope: FleetDispatchScope) async throws -> [FleetDispatchTrip] {
        try await list(path: scope == .mms ? "/api/mms-fleet/dispatch/pending" : "/api/travel-desk/trips/pending", token: token)
    }

    static func listAssigned(token: String, scope: FleetDispatchScope) async throws -> [FleetDispatchTrip] {
        try await list(path: scope == .mms ? "/api/mms-fleet/dispatch/assigned" : "/api/travel-desk/trips/assigned", token: token)
    }

    static func listVehicles(token: String, scope: FleetDispatchScope) async throws -> [FleetDispatchVehicle] {
        try await list(path: scope == .mms ? "/api/mms-fleet/dispatch/vehicles" : "/api/travel-desk/vehicles", token: token)
    }

    static func listDrivers(token: String, scope: FleetDispatchScope) async throws -> [FleetDispatchDriver] {
        try await list(path: scope == .mms ? "/api/mms-fleet/dispatch/drivers" : "/api/travel-desk/drivers", token: token)
    }

    static func allocate(
        token: String,
        scope: FleetDispatchScope,
        tripId: String,
        draft: FleetAllocationDraft
    ) async throws {
        let body = AllocateRequest(
            siteVisitId: tripId,
            vehicleId: draft.vehicleId,
            pickupTime: draft.pickupTime,
            pricingMode: draft.pricingMode,
            driverName: draft.driverName,
            driverPhone: draft.driverPhone,
            kmRate: draft.pricingMode == "km" ? draft.amount : nil,
            packageAmount: draft.pricingMode == "package" ? draft.amount : nil
        )
        try await mutate(
            path: scope == .mms ? "/api/mms-fleet/dispatch/allocate" : "/api/travel-desk/trips/allocate",
            token: token,
            body: body
        )
    }

    static func unassign(token: String, scope: FleetDispatchScope, tripId: String) async throws {
        try await mutate(
            path: scope == .mms ? "/api/mms-fleet/dispatch/unassign" : "/api/travel-desk/trips/unallocate",
            token: token,
            body: TripRequest(siteVisitId: tripId)
        )
    }

    static func completeOffline(
        token: String,
        scope: FleetDispatchScope,
        tripId: String,
        draft: FleetOfflineCompletionDraft
    ) async throws {
        try await mutate(
            path: scope == .mms ? "/api/mms-fleet/dispatch/complete-offline" : "/api/travel-desk/trips/complete-offline",
            token: token,
            body: CompleteOfflineRequest(
                siteVisitId: tripId,
                fleetType: draft.fleetType,
                vehicleId: draft.vehicleId,
                agencyName: draft.agencyName,
                packageAmount: draft.packageAmount,
                kmRate: draft.kmRate,
                distanceKm: draft.distanceKm,
                driverName: draft.driverName,
                driverPhone: draft.driverPhone,
                beta: draft.beta,
                beta2: draft.beta2,
                tollAmount: draft.tollAmount,
                hillCharge: draft.hillCharge,
                outstationCharge: draft.outstationCharge,
                permitCharge: draft.permitCharge,
                permitTax: draft.permitTax,
                standingCharge: draft.standingCharge,
                standingTimeMinutes: draft.standingTimeMinutes,
                standingWithAc: draft.standingWithAc,
                startKm: draft.startKm,
                endKm: draft.endKm
            )
        )
    }

    static func listAgencyStaff(token: String) async throws -> [FleetAgencyStaff] {
        try await list(path: "/api/travel-desk/staff", token: token)
    }

    static func createAgencyStaff(token: String, name: String, phone: String, whatsapp: String?) async throws {
        try await mutate(
            path: "/api/travel-desk/staff/create",
            token: token,
            body: AgencyStaffRequest(id: nil, name: name, phone: phone, whatsapp: whatsapp, status: nil)
        )
    }

    static func updateAgencyStaff(
        token: String,
        id: String,
        name: String? = nil,
        phone: String? = nil,
        whatsapp: String? = nil,
        status: String? = nil
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/staff/update",
            token: token,
            body: AgencyStaffRequest(id: id, name: name, phone: phone, whatsapp: whatsapp, status: status)
        )
    }

    static func getAgencySettings(token: String) async throws -> FleetAgencySettings {
        let data = try await request(path: "/api/travel-desk/settings", token: token)
        let response = try await BackgroundJSONDecoder.decode(SettingsResponse.self, from: data)
        guard response.success else {
            throw FleetDispatchAPIError.server(statusCode: 200, message: response.error ?? "Failed to load fleet settings.")
        }
        return response.settings ?? .empty
    }

    static func updateAgencySettings(token: String, settings: FleetAgencySettings) async throws -> FleetAgencySettings {
        let data = try await request(
            path: "/api/travel-desk/settings/update",
            token: token,
            method: "POST",
            body: settings
        )
        let response = try await BackgroundJSONDecoder.decode(SettingsResponse.self, from: data)
        guard response.success else {
            throw FleetDispatchAPIError.server(statusCode: 200, message: response.error ?? "Failed to update fleet settings.")
        }
        return response.settings ?? settings
    }

    static func uploadAgencyPhoto(token: String, data: Data) async throws -> String {
        let responseData = try await request(
            path: "/api/travel-desk/storage/upload",
            token: token,
            method: "POST",
            rawBody: data,
            contentType: "image/jpeg"
        )
        let response = try await BackgroundJSONDecoder.decode(StorageResponse.self, from: responseData)
        guard response.success, let storageId = response.storageId?.nonBlank else {
            throw FleetDispatchAPIError.server(statusCode: 200, message: response.error ?? "Photo upload failed.")
        }
        return storageId
    }

    static func createDriver(
        token: String,
        scope: FleetDispatchScope,
        name: String,
        phone: String,
        address: String?,
        actingStaffId: String? = nil
    ) async throws {
        if scope == .mms {
            let staffId = try requiredStaffId(actingStaffId)
            try await convexMutate(
                path: "marketing/fleetDrivers:create",
                arguments: MMSDriverCreateRequest(
                    actingStaffId: staffId,
                    name: name,
                    phone: phone,
                    address: address
                )
            )
            return
        }
        try await mutate(
            path: "/api/travel-desk/drivers/create",
            token: token,
            body: DriverCreateRequest(name: name, phone: phone, address: address)
        )
    }

    static func updateDriver(
        token: String,
        scope: FleetDispatchScope,
        id: String,
        name: String?,
        phone: String?,
        address: String?,
        actingStaffId: String? = nil
    ) async throws {
        if scope == .mms {
            let staffId = try requiredStaffId(actingStaffId)
            try await convexMutate(
                path: "marketing/fleetDrivers:update",
                arguments: MMSDriverUpdateRequest(
                    actingStaffId: staffId,
                    id: id,
                    name: name,
                    phone: phone,
                    address: address
                )
            )
            return
        }
        try await mutate(
            path: "/api/travel-desk/drivers/update",
            token: token,
            body: DriverUpdateRequest(id: id, name: name, phone: phone, address: address)
        )
    }

    static func setDriverStatus(
        token: String,
        scope: FleetDispatchScope,
        id: String,
        status: String,
        actingStaffId: String? = nil
    ) async throws {
        if scope == .mms {
            let staffId = try requiredStaffId(actingStaffId)
            try await convexMutate(
                path: "marketing/fleetDrivers:setStatus",
                arguments: MMSDriverStatusRequest(actingStaffId: staffId, id: id, status: status)
            )
            return
        }
        try await mutate(
            path: "/api/travel-desk/drivers/set-status",
            token: token,
            body: DriverStatusRequest(id: id, status: status)
        )
    }

    static func createVehicle(
        token: String,
        scope: FleetDispatchScope,
        vehicleNumber: String,
        type: String?,
        capacity: Int?,
        defaultDriverName: String?,
        defaultDriverPhone: String?,
        actingStaffId: String? = nil
    ) async throws {
        if scope == .mms {
            let staffId = try requiredStaffId(actingStaffId)
            try await convexMutate(
                path: "marketing/vehicles:create",
                arguments: MMSVehicleCreateRequest(
                    actingStaffId: staffId,
                    vehicleNumber: vehicleNumber,
                    type: type,
                    capacity: capacity,
                    defaultDriverName: defaultDriverName,
                    defaultDriverPhone: defaultDriverPhone
                )
            )
            return
        }
        try await mutate(
            path: "/api/travel-desk/vehicles/create",
            token: token,
            body: VehicleCreateRequest(
                vehicleNumber: vehicleNumber,
                type: type,
                capacity: capacity,
                defaultDriverName: defaultDriverName,
                defaultDriverPhone: defaultDriverPhone
            )
        )
    }

    static func createAgencyVehicle(
        token: String,
        vehicleNumber: String,
        type: String?,
        capacity: Int?,
        defaultDriverName: String?,
        defaultDriverPhone: String?
    ) async throws {
        try await createVehicle(
            token: token,
            scope: .agency,
            vehicleNumber: vehicleNumber,
            type: type,
            capacity: capacity,
            defaultDriverName: defaultDriverName,
            defaultDriverPhone: defaultDriverPhone
        )
    }

    private static func list<Item: Decodable>(path: String, token: String) async throws -> [Item] {
        let data = try await request(path: path, token: token)
        do {
            let response = try await BackgroundJSONDecoder.decode(ListResponse<Item>.self, from: data)
            guard response.success else {
                throw FleetDispatchAPIError.server(statusCode: 200, message: response.error ?? "Fleet request failed.")
            }
            return response.rows
        } catch let error as FleetDispatchAPIError {
            throw error
        } catch {
            throw FleetDispatchAPIError.decoding(error)
        }
    }

    private static func mutate<Body: Encodable>(path: String, token: String, body: Body) async throws {
        let data = try await request(path: path, token: token, method: "POST", body: body)
        do {
            let response = try await BackgroundJSONDecoder.decode(MutationResponse.self, from: data)
            guard response.success else {
                throw FleetDispatchAPIError.server(statusCode: 200, message: response.error ?? "Fleet action failed.")
            }
        } catch let error as FleetDispatchAPIError {
            throw error
        } catch {
            throw FleetDispatchAPIError.decoding(error)
        }
    }

    private static func requiredStaffId(_ value: String?) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FleetDispatchAPIError.server(statusCode: 400, message: "Your staff profile is unavailable. Please sign in again.")
        }
        return value
    }

    private static func convexMutate<Arguments: Encodable>(
        path: String,
        arguments: Arguments
    ) async throws {
        guard let url = URL(string: "\(convexURL)/api/mutation") else {
            throw FleetDispatchAPIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ConvexMutationEnvelope(path: path, args: arguments)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FleetDispatchAPIError.server(
                statusCode: http.statusCode,
                message: "Fleet action failed (\(http.statusCode))."
            )
        }
        let result = try await BackgroundJSONDecoder.decode(ConvexMutationResponse.self, from: data)
        guard result.status == "success" else {
            let message = result.errorMessage?.components(separatedBy: "\n").last(where: { !$0.isEmpty })
                ?? "Fleet action failed."
            throw FleetDispatchAPIError.server(statusCode: 400, message: message)
        }
    }

    private static func request(
        path: String,
        token: String,
        method: String = "GET"
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw FleetDispatchAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private static func request<Body: Encodable>(
        path: String,
        token: String,
        method: String,
        body: Body
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw FleetDispatchAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private static func request(
        path: String,
        token: String,
        method: String,
        rawBody: Data,
        contentType: String
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw FleetDispatchAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = rawBody
        return try await perform(request)
    }

    private static func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit()
            throw FleetDispatchAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"])
                ?? "Fleet request failed (\(http.statusCode))."
            throw FleetDispatchAPIError.server(statusCode: http.statusCode, message: message)
        }
        return data
    }
}
