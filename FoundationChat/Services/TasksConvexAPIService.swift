import Foundation

/// HTTP client for Convex-based Tasks endpoints.
enum TasksConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    // MARK: - Response wrappers

    private struct TasksListResponse: Decodable {
        let success: Bool
        let total: Int?
        let tasks: [ConvexTask]?
        let error: String?
    }

    private struct DailyTaskManagerResponse: Decodable {
        let success: Bool
        let tasks: [DailyTask]?
        let teamIds: [String]?
        let scope: String?
        let error: String?
    }

    private struct TaskSummaryResponse: Decodable {
        let success: Bool
        let summary: ConvexTaskSummary?
        let total: Int?
        let notStarted: Int?
        let pending: Int?
        let inProgress: Int?
        let completed: Int?
        let delayed: Int?
        let overallPercent: Double?
        let overallProgress: Double?
        let error: String?
    }

    private struct TaskGetResponse: Decodable {
        let success: Bool
        let task: ConvexTask?
        let error: String?
    }

    private struct TaskActionResponse: Decodable {
        let success: Bool
        let taskId: String?
        let updateId: String?
        let task: ConvexTask?
        let error: String?
    }

    private struct TaskResourcesResponse: Decodable {
        let success: Bool
        let resources: [TaskResourceEntry]?
        let error: String?
    }

    private struct TaskTimelineResponse: Decodable {
        let success: Bool
        let updates: [ConvexTaskUpdate]?
        let error: String?
    }

    // MARK: - Reads

    static func getMyTasks(token: String) async throws -> [ConvexTask] {
        let data = try await get(path: "/api/tasks/my", token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(TasksListResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load tasks")
        }
        return wrapper.tasks ?? []
    }

    static func getTaskManagerTasks(token: String, today: String? = nil) async throws -> DailyTaskManagerPayload {
        var path = "/api/dailyTasks/listForTaskManager"
        if let today, !today.isEmpty {
            path += "?today=\(urlEncode(today))"
        }
        let data = try await get(path: path, token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(DailyTaskManagerResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load task manager")
        }
        return DailyTaskManagerPayload(
            tasks: wrapper.tasks ?? [],
            teamIds: Set(wrapper.teamIds ?? []),
            scope: wrapper.scope
        )
    }

    static func getPendingTaskReminders(token: String, today: String, limit: Int = 10) async throws -> [DailyTask] {
        let safeLimit = min(50, max(1, limit))
        let path = "/api/dailyTasks/listPendingRemindersForStaff?today=\(urlEncode(today))&limit=\(safeLimit)"
        let data = try await get(path: path, token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(DailyTaskManagerResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load pending task reminders")
        }
        return wrapper.tasks ?? []
    }

    static func getMySummary(token: String) async throws -> ConvexTaskSummary {
        let data = try await get(path: "/api/tasks/my/summary", token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskSummaryResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load summary")
        }
        if let summary = wrapper.summary { return summary }
        return ConvexTaskSummary(
            total: wrapper.total,
            notStarted: wrapper.notStarted,
            pending: wrapper.pending,
            inProgress: wrapper.inProgress,
            completed: wrapper.completed,
            delayed: wrapper.delayed,
            overallPercent: wrapper.overallPercent,
            overallProgress: wrapper.overallProgress
        )
    }

    static func getTask(token: String, taskId: String) async throws -> ConvexTask {
        let path = "/api/projects/tasks/get?id=\(urlEncode(taskId))"
        let data = try await get(path: path, token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskGetResponse.self, from: data)
        guard wrapper.success, let task = wrapper.task else {
            throw HRConvexAPIError.server(wrapper.error ?? "Task not found")
        }
        return task
    }

    static func getTaskResources(token: String, taskId: String) async throws -> [TaskResourceEntry] {
        let path = "/api/projects/tasks/resources?taskId=\(urlEncode(taskId))"
        let data = try await get(path: path, token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskResourcesResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load resources")
        }
        return wrapper.resources ?? []
    }

    static func getTaskTimeline(token: String, taskId: String) async throws -> [ConvexTaskUpdate] {
        let path = "/api/projects/tasks/updates?taskId=\(urlEncode(taskId))"
        let data = try await get(path: path, token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskTimelineResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load timeline")
        }
        return (wrapper.updates ?? []).sorted {
            ($0.creationTime ?? 0) > ($1.creationTime ?? 0)
        }
    }

    // MARK: - Writes

    static func updateProgress(token: String, taskId: String, progress: Int, comment: String?) async throws {
        var body: [String: Any] = [
            "id": taskId,
            "progress": progress
        ]
        if let comment, !comment.isEmpty {
            body["comment"] = comment
        }
        let data = try await post(path: "/api/projects/tasks/update-progress", token: token, jsonBody: body)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update progress")
        }
    }

    static func updateStatus(token: String, taskId: String, status: String) async throws {
        let body: [String: Any] = [
            "id": taskId,
            "status": status
        ]
        let data = try await post(path: "/api/projects/tasks/update", token: token, jsonBody: body)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update task")
        }
    }

    /// Task-Manager daily task status change (e.g. out-of-station handoff
    /// Complete / Cancel). Mirrors Android `dailyTasks/updateStatus`; distinct
    /// from `updateStatus` above, which targets project tasks.
    static func updateDailyTaskStatus(token: String, id: String, status: String) async throws {
        let body: [String: Any] = [
            "id": id,
            "status": status
        ]
        let data = try await post(path: "/api/dailyTasks/updateStatus", token: token, jsonBody: body)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update task")
        }
    }

    static func updateTask(
        token: String,
        taskId: String,
        status: String?,
        progress: Int?,
        actualStartDate: String?,
        actualEndDate: String?
    ) async throws {
        var body: [String: Any] = ["id": taskId]
        if let status { body["status"] = status }
        if let progress { body["progress"] = progress }
        if let actualStartDate { body["actualStartDate"] = actualStartDate }
        if let actualEndDate { body["actualEndDate"] = actualEndDate }
        let data = try await post(path: "/api/projects/tasks/update", token: token, jsonBody: body)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update task")
        }
    }

    static func addTimelineUpdate(
        token: String,
        taskId: String,
        date: String,
        todaysUpdate: String?,
        blocker: String?,
        tomorrowsPlan: String?,
        progressSnapshot: Int,
        images: [TaskUpdateImage]? = nil
    ) async throws {
        var body: [String: Any] = [
            "taskId": taskId,
            "date": date,
            "progressSnapshot": progressSnapshot
        ]
        if let todaysUpdate, !todaysUpdate.isEmpty { body["todaysUpdate"] = todaysUpdate }
        if let blocker, !blocker.isEmpty { body["blocker"] = blocker }
        if let tomorrowsPlan, !tomorrowsPlan.isEmpty { body["tomorrowsPlan"] = tomorrowsPlan }
        if let images, !images.isEmpty {
            body["images"] = images.map { image in
                var payload: [String: Any] = ["storageId": image.storageId]
                if let url = image.url, !url.isEmpty { payload["url"] = url }
                if let name = image.name, !name.isEmpty { payload["name"] = name }
                return payload
            }
        }
        let data = try await post(path: "/api/projects/tasks/add-update", token: token, jsonBody: body)
        let wrapper = try await BackgroundJSONDecoder.decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to add update")
        }
    }

    static func addUpdate(token: String, taskId: String, comment: String) async throws {
        try await addTimelineUpdate(
            token: token,
            taskId: taskId,
            date: AppModuleFormatters.ymd.string(from: Date()),
            todaysUpdate: comment,
            blocker: nil,
            tomorrowsPlan: nil,
            progressSnapshot: 0
        )
    }

    // MARK: - HTTP helpers

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func get(path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response, request: request)
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
        try checkHTTPError(data: data, response: response, request: request)
        return data
    }

    private static func checkHTTPError(data: Data, response: URLResponse, request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit(for: request, responseData: data)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw HRConvexAPIError.unauthorized(error)
            }
            throw HRConvexAPIError.unauthorized("Unauthorized")
        }
        if http.statusCode >= 400 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw HRConvexAPIError.server(error)
            }
            throw HRConvexAPIError.server("Request failed (\(http.statusCode))")
        }
    }
}
