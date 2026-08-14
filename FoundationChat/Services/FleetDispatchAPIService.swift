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
        let agencies: [Item]?
        let error: String?

        var rows: [Item] { trips ?? vehicles ?? drivers ?? staff ?? agencies ?? data ?? [] }
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
        // Android's CreateDriverRequest carries a non-null `category`
        // ("old" | "new" MMS contract value). Omitted (nil) when the UI
        // doesn't collect it — encodeIfPresent drops it, matching today's
        // agency create which never sent it. See VERIFY note.
        let category: String?
    }

    private struct DriverUpdateRequest: Encodable {
        let id: String
        let name: String?
        let phone: String?
        let address: String?
        let category: String?
    }

    private struct DriverStatusRequest: Encodable {
        let id: String
        let status: String
    }

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
        category: String? = nil,
        actingStaffId: String? = nil
    ) async throws {
        // Both scopes now go over the REST transport (api-mfpl), mirroring
        // Android's TravelDeskApi.createDriver / createMmsDriver. The MMS
        // route resolves the staff principal from the bearer token, so the
        // old actingStaffId / raw-Convex `marketing/fleetDrivers:create`
        // path is no longer needed (actingStaffId retained for source compat).
        try await mutate(
            path: scope == .mms
                ? "/api/mms-fleet/dispatch/drivers/create"
                : "/api/travel-desk/drivers/create",
            token: token,
            body: DriverCreateRequest(name: name, phone: phone, address: address, category: category)
        )
    }

    static func updateDriver(
        token: String,
        scope: FleetDispatchScope,
        id: String,
        name: String?,
        phone: String?,
        address: String?,
        category: String? = nil,
        actingStaffId: String? = nil
    ) async throws {
        try await mutate(
            path: scope == .mms
                ? "/api/mms-fleet/dispatch/drivers/update"
                : "/api/travel-desk/drivers/update",
            token: token,
            body: DriverUpdateRequest(id: id, name: name, phone: phone, address: address, category: category)
        )
    }

    static func setDriverStatus(
        token: String,
        scope: FleetDispatchScope,
        id: String,
        status: String,
        actingStaffId: String? = nil
    ) async throws {
        try await mutate(
            path: scope == .mms
                ? "/api/mms-fleet/dispatch/drivers/set-status"
                : "/api/travel-desk/drivers/set-status",
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

    // MARK: - Vehicles (update / status)

    /// Edit an agency vehicle. Android: TravelDeskApi.updateVehicle →
    /// POST api/travel-desk/vehicles/update (UpdateVehicleRequest). The vehicle
    /// *status* change is a `status` field on this same route in Android — there
    /// is no separate status-change endpoint. MMS in-house vehicles have no
    /// update route in Android's TravelDeskApi (only travel-desk vehicles do),
    /// so this is agency-scope only.
    static func updateVehicle(
        token: String,
        draft: FleetVehicleUpdateDraft
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/vehicles/update",
            token: token,
            body: draft
        )
    }

    // MARK: - Trip management

    /// Take an allocated trip back to Pending. Agency → travel-desk/unallocate;
    /// MMS/agency-allotted → mms-fleet/dispatch/unassign (a distinct route — the
    /// travel-desk unallocate rejects staff sessions). Mirrors Android
    /// TravelDeskApi.unallocate / unassignMms.
    static func unassign(
        token: String,
        scope: FleetDispatchScope,
        tripId: String
    ) async throws {
        try await mutate(
            path: scope == .mms
                ? "/api/mms-fleet/dispatch/unassign"
                : "/api/travel-desk/trips/unallocate",
            token: token,
            body: SiteVisitRequest(siteVisitId: tripId)
        )
    }

    /// Re-send the driver's trip WhatsApp link. Android: single travel-desk
    /// route used for both scopes.
    static func resendDriverWhatsapp(
        token: String,
        tripId: String
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/trips/resend-driver-whatsapp",
            token: token,
            body: SiteVisitRequest(siteVisitId: tripId)
        )
    }

    /// Finalize billing for a completed trip. Android: finalizeBilling →
    /// POST api/travel-desk/trips/finalize-billing (FinalizeTravelDeskBillingRequest).
    static func finalizeBilling(
        token: String,
        draft: FleetFinalizeBillingDraft
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/trips/finalize-billing",
            token: token,
            body: draft
        )
    }

    /// Bill a cancelled trip (cancellation/waiting allowance + custom lines).
    /// Android: finalizeCancellationBilling → cancellation-billing.
    static func finalizeCancellationBilling(
        token: String,
        tripId: String,
        customCharges: [FleetAppliedCharge]? = nil
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/trips/cancellation-billing",
            token: token,
            body: CancellationBillingRequest(siteVisitId: tripId, customCharges: customCharges)
        )
    }

    /// Submit an extra-km claim for review. Android: submitExtraKmClaim → extra-km.
    static func submitExtraKmClaim(
        token: String,
        tripId: String,
        extraKm: Double
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/trips/extra-km",
            token: token,
            body: ExtraKmRequest(siteVisitId: tripId, extraKm: extraKm)
        )
    }

    /// Attach odometer photos / readings evidence. Android: submitEvidence.
    static func submitEvidence(
        token: String,
        draft: FleetEvidenceDraft
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/trips/evidence",
            token: token,
            body: draft
        )
    }

    /// Record a non-completion status (client not met / rescheduled, etc).
    /// Android: updateTripStatus → status-update.
    static func updateTripStatus(
        token: String,
        draft: FleetStatusUpdateDraft
    ) async throws {
        try await mutate(
            path: "/api/travel-desk/trips/status-update",
            token: token,
            body: draft
        )
    }

    /// Complete a trip that ran offline (manual km/charges). Android:
    /// completeOfflineMms (mms-fleet) / completeOfflineAgency (travel-desk).
    static func completeOffline(
        token: String,
        scope: FleetDispatchScope,
        draft: FleetOfflineCompletionDraft
    ) async throws {
        try await mutate(
            path: scope == .mms
                ? "/api/mms-fleet/dispatch/complete-offline"
                : "/api/travel-desk/trips/complete-offline",
            token: token,
            body: draft
        )
    }

    // MARK: - MMS dispatch (agencies)

    /// External travel agencies an MMS dispatcher can allot a trip to.
    /// Android: listMmsAgencies → GET api/mms-fleet/dispatch/agencies.
    static func listAgencies(token: String) async throws -> [FleetDispatchAgency] {
        try await list(path: "/api/mms-fleet/dispatch/agencies", token: token)
    }

    /// Allot a visit to an external agency (agency then assigns the cab).
    /// Android: allotMmsAgency → POST api/mms-fleet/dispatch/allot-agency.
    static func allotAgency(
        token: String,
        tripId: String,
        travelAgencyId: String
    ) async throws {
        try await mutate(
            path: "/api/mms-fleet/dispatch/allot-agency",
            token: token,
            body: AllotAgencyRequestBody(siteVisitId: tripId, travelAgencyId: travelAgencyId)
        )
    }

    // MARK: - Small request bodies

    private struct SiteVisitRequest: Encodable {
        let siteVisitId: String
    }

    private struct AllotAgencyRequestBody: Encodable {
        let siteVisitId: String
        let travelAgencyId: String
    }

    private struct ExtraKmRequest: Encodable {
        let siteVisitId: String
        let extraKm: Double
    }

    private struct CancellationBillingRequest: Encodable {
        let siteVisitId: String
        let customCharges: [FleetAppliedCharge]?
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
