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

    private struct TaskSummaryResponse: Decodable {
        let success: Bool
        let summary: ConvexTaskSummary?
        let total: Int?
        let pending: Int?
        let inProgress: Int?
        let completed: Int?
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
        let error: String?
    }

    // MARK: - Reads

    static func getMyTasks(token: String) async throws -> [ConvexTask] {
        let data = try await get(path: "/api/tasks/my", token: token)
        let wrapper = try JSONDecoder().decode(TasksListResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load tasks")
        }
        return wrapper.tasks ?? []
    }

    static func getMySummary(token: String) async throws -> ConvexTaskSummary {
        let data = try await get(path: "/api/tasks/my/summary", token: token)
        let wrapper = try JSONDecoder().decode(TaskSummaryResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load summary")
        }
        if let summary = wrapper.summary { return summary }
        return ConvexTaskSummary(
            total: wrapper.total,
            pending: wrapper.pending,
            inProgress: wrapper.inProgress,
            completed: wrapper.completed,
            overallPercent: wrapper.overallPercent,
            overallProgress: wrapper.overallProgress
        )
    }

    static func getTask(token: String, taskId: String) async throws -> ConvexTask {
        let path = "/api/projects/tasks/get?id=\(urlEncode(taskId))"
        let data = try await get(path: path, token: token)
        let wrapper = try JSONDecoder().decode(TaskGetResponse.self, from: data)
        guard wrapper.success, let task = wrapper.task else {
            throw HRConvexAPIError.server(wrapper.error ?? "Task not found")
        }
        return task
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
        let wrapper = try JSONDecoder().decode(TaskActionResponse.self, from: data)
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
        let wrapper = try JSONDecoder().decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update task")
        }
    }

    static func addUpdate(token: String, taskId: String, comment: String) async throws {
        let body: [String: Any] = [
            "id": taskId,
            "comment": comment
        ]
        let data = try await post(path: "/api/projects/tasks/add-update", token: token, jsonBody: body)
        let wrapper = try JSONDecoder().decode(TaskActionResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to add update")
        }
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
