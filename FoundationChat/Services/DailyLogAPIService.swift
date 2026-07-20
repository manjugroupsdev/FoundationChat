import Foundation

enum DailyLogAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct DailyLogListResponse: Decodable {
        let success: Bool
        let logs: [DailyLogEntry]?
        let error: String?
    }

    private struct DailyLogCreateResponse: Decodable {
        let success: Bool
        let id: String?
        let error: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case _id
            case success, error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = try container.decode(Bool.self, forKey: .success)
            id = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: ._id)
            error = try container.decodeIfPresent(String.self, forKey: .error)
        }
    }

    private struct MaterialsResponse: Decodable {
        let success: Bool
        let materials: [DailyLogMaterialCatalogItem]?
        let error: String?
    }

    private struct SimpleResponse: Decodable {
        let success: Bool
        let error: String?
    }

    private struct MyDprResponse: Decodable {
        let success: Bool
        let recipients: [DprRecipient]?
        let reports: [DprReport]?
        let error: String?
    }

    private struct DprRecipientsResponse: Decodable {
        let success: Bool
        let recipients: [DprRecipient]?
        let error: String?
    }

    private struct DprReportsResponse: Decodable {
        let success: Bool
        let reports: [DprReport]?
        let error: String?
    }

    private struct SendDprResponse: Decodable {
        let success: Bool
        let skipped: Bool?
        let sentCount: Int?
        let failedCount: Int?
        let error: String?
    }

    struct SendDprResult: Sendable {
        let skipped: Bool
        let sentCount: Int
        let failedCount: Int
    }

    @discardableResult
    static func createDailyLog(
        token: String,
        projectId: String,
        date: String,
        weather: String?,
        siteConditions: String?,
        workSummary: String,
        labourCount: Int?,
        labourHours: Double?,
        materialsUsed: [DailyLogMaterial],
        equipmentUsed: [DailyLogEquipment],
        issuesEncountered: String?,
        safetyObservations: String?,
        supervisorName: String?,
        attachments: [DailyLogAttachment]
    ) async throws -> String {
        var body: [String: Any] = [
            "projectId": projectId,
            "date": date,
            "workSummary": workSummary
        ]
        if let weather, !weather.isEmpty { body["weather"] = weather }
        if let siteConditions, !siteConditions.isEmpty { body["siteConditions"] = siteConditions }
        if let labourCount { body["labourCount"] = labourCount }
        if let labourHours { body["labourHours"] = labourHours }
        if !materialsUsed.isEmpty {
            body["materialsUsed"] = materialsUsed.map { item in
                var payload: [String: Any] = [
                    "name": item.name,
                    "quantity": item.quantity
                ]
                if let unit = item.unit?.nonBlank { payload["unit"] = unit }
                return payload
            }
        }
        if !equipmentUsed.isEmpty {
            body["equipmentUsed"] = equipmentUsed.map { ["name": $0.name, "hours": $0.hours] }
        }
        if let issuesEncountered, !issuesEncountered.isEmpty { body["issuesEncountered"] = issuesEncountered }
        if let safetyObservations, !safetyObservations.isEmpty { body["safetyObservations"] = safetyObservations }
        if let supervisorName, !supervisorName.isEmpty { body["supervisorName"] = supervisorName }
        if !attachments.isEmpty {
            body["attachments"] = attachments.map { attachment in
                var payload: [String: Any] = ["storageId": attachment.storageId]
                if let url = attachment.url?.nonBlank { payload["url"] = url }
                if let type = attachment.type?.nonBlank { payload["type"] = type }
                if let name = attachment.name?.nonBlank { payload["name"] = name }
                return payload
            }
        }

        let data = try await post(path: "/api/projects/daily-log/create", token: token, jsonBody: body)
        let wrapper = try JSONDecoder().decode(DailyLogCreateResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to save daily log")
        }
        return wrapper.id ?? UUID().uuidString
    }

    static func listMyDailyLogs(token: String) async throws -> [DailyLogEntry] {
        let data = try await get(path: "/api/projects/daily-log/mine", token: token)
        let wrapper = try JSONDecoder().decode(DailyLogListResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load daily logs")
        }
        return wrapper.logs ?? []
    }

    static func listDailyLogs(token: String, projectId: String) async throws -> [DailyLogEntry] {
        let data = try await get(
            path: "/api/projects/daily-log/list",
            token: token,
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        let wrapper = try JSONDecoder().decode(DailyLogListResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load daily logs")
        }
        return wrapper.logs ?? []
    }

    static func loadRecentLogs(token: String, projects: [ProjectSummary]) async throws -> [DailyLogEntry] {
        if let mine = try? await listMyDailyLogs(token: token) {
            return mine.sortedByDateDescending()
        }

        let aggregated = await withTaskGroup(of: [DailyLogEntry].self) { group in
            for project in projects.prefix(30) {
                group.addTask {
                    let logs = (try? await listDailyLogs(token: token, projectId: project.id)) ?? []
                    return logs.map { log in
                        var resolved = log
                        if resolved.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                            resolved.projectName = project.name
                        }
                        return resolved
                    }
                }
            }

            var rows: [DailyLogEntry] = []
            for await projectLogs in group {
                rows.append(contentsOf: projectLogs)
            }
            return rows
        }
        return aggregated.sortedByDateDescending()
    }

    static func listMaterials(token: String) async throws -> [DailyLogMaterialCatalogItem] {
        let data = try await get(path: "/api/materials", token: token)
        let wrapper = try JSONDecoder().decode(MaterialsResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load materials")
        }
        return wrapper.materials ?? []
    }

    static func getMyDpr(token: String, projects: [ProjectSummary]) async throws -> ([DprRecipient], [DprReport]) {
        if let mine = try? await getMyDprAggregate(token: token) {
            return mine
        }

        let aggregate = await withTaskGroup(of: ([DprRecipient], [DprReport]).self) { group in
            for project in projects.prefix(30) {
                group.addTask {
                    async let recipients = try? listDprRecipients(token: token, projectId: project.id)
                    async let reports = try? listDprReports(token: token, projectId: project.id)
                    let resolvedRecipients = (await recipients ?? []).map { recipient in
                        var resolved = recipient
                        if resolved.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                            resolved.projectName = project.name
                        }
                        return resolved
                    }
                    let resolvedReports = (await reports ?? []).map { report in
                        var resolved = report
                        if resolved.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                            resolved.projectName = project.name
                        }
                        return resolved
                    }
                    return (resolvedRecipients, resolvedReports)
                }
            }

            var recipients: [DprRecipient] = []
            var reports: [DprReport] = []
            for await (projectRecipients, projectReports) in group {
                recipients.append(contentsOf: projectRecipients)
                reports.append(contentsOf: projectReports)
            }
            return (recipients, reports)
        }
        return (aggregate.0, aggregate.1.sortedByDateDescending())
    }

    private static func getMyDprAggregate(token: String) async throws -> ([DprRecipient], [DprReport]) {
        let data = try await get(path: "/api/projects/dpr/mine", token: token)
        let wrapper = try JSONDecoder().decode(MyDprResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load DPR")
        }
        return (wrapper.recipients ?? [], wrapper.reports ?? [])
    }

    static func listDprRecipients(token: String, projectId: String) async throws -> [DprRecipient] {
        let data = try await get(
            path: "/api/projects/dpr/recipients",
            token: token,
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        let wrapper = try JSONDecoder().decode(DprRecipientsResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load recipients")
        }
        return wrapper.recipients ?? []
    }

    static func listDprReports(token: String, projectId: String) async throws -> [DprReport] {
        let data = try await get(
            path: "/api/projects/dpr/reports",
            token: token,
            queryItems: [URLQueryItem(name: "projectId", value: projectId)]
        )
        let wrapper = try JSONDecoder().decode(DprReportsResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load DPR history")
        }
        return wrapper.reports ?? []
    }

    static func addDprRecipient(
        token: String,
        projectId: String,
        staffId: String?,
        name: String,
        phone: String
    ) async throws {
        var body: [String: Any] = [
            "projectId": projectId,
            "name": name,
            "phone": phone
        ]
        if let staffId, !staffId.isEmpty { body["staffId"] = staffId }
        let data = try await post(path: "/api/projects/dpr/recipients/add", token: token, jsonBody: body)
        let wrapper = try JSONDecoder().decode(SimpleResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to add recipient")
        }
    }

    static func updateDprRecipient(token: String, id: String, isActive: Bool) async throws {
        let data = try await post(
            path: "/api/projects/dpr/recipients/update",
            token: token,
            jsonBody: ["id": id, "isActive": isActive]
        )
        let wrapper = try JSONDecoder().decode(SimpleResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update recipient")
        }
    }

    static func removeDprRecipient(token: String, id: String) async throws {
        let data = try await post(path: "/api/projects/dpr/recipients/remove", token: token, jsonBody: ["id": id])
        let wrapper = try JSONDecoder().decode(SimpleResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to remove recipient")
        }
    }

    static func sendDprNow(token: String, projectId: String) async throws -> SendDprResult {
        let data = try await post(path: "/api/projects/dpr/send", token: token, jsonBody: ["projectId": projectId])
        let wrapper = try JSONDecoder().decode(SendDprResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to send DPR")
        }
        return SendDprResult(
            skipped: wrapper.skipped ?? false,
            sentCount: wrapper.sentCount ?? 0,
            failedCount: wrapper.failedCount ?? 0
        )
    }

    private static func get(path: String, token: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)\(path)")
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response)
        return data
    }

    private static func post(path: String, token: String, jsonBody: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response)
        return data
    }

    private static func checkHTTPError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit()
        }
        guard (200..<300).contains(http.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["error"] as? String {
                throw HRConvexAPIError.server(message)
            }
            throw HRConvexAPIError.server("HTTP \(http.statusCode)")
        }
    }
}

private extension Array where Element == DailyLogEntry {
    func sortedByDateDescending() -> [DailyLogEntry] {
        sorted { ($0.date ?? "") > ($1.date ?? "") }
    }
}

private extension Array where Element == DprReport {
    func sortedByDateDescending() -> [DprReport] {
        sorted { ($0.date ?? "") > ($1.date ?? "") }
    }
}
