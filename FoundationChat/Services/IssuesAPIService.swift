import Foundation

enum IssuesAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct IssuesListResponse: Decodable {
        let success: Bool
        let issues: [ProjectIssue]
        let error: String?
    }

    private struct CreateIssueRequest: Encodable {
        let projectId: String
        let title: String
        let description: String?
        let audioStorageId: String?
        let audioFileName: String?
        let audioFileType: String?
        let audioFileSize: Int?
        let audioDurationSeconds: Int?
    }

    private struct CreateIssueResponse: Decodable {
        let success: Bool
        let id: String?
        let error: String?
    }

    static func listMyIssues(token: String) async throws -> [ProjectIssue] {
        let data = try await get(path: "/api/issues/my", token: token)
        let wrapper = try await BackgroundJSONDecoder.decode(IssuesListResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load issues")
        }
        return wrapper.issues.sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    static func createIssue(
        token: String,
        projectId: String,
        title: String,
        description: String?,
        audioStorageId: String? = nil,
        audioFileName: String? = nil,
        audioFileType: String? = nil,
        audioFileSize: Int? = nil,
        audioDurationSeconds: Int? = nil
    ) async throws {
        let request = CreateIssueRequest(
            projectId: projectId,
            title: title,
            description: description?.nonBlank,
            audioStorageId: audioStorageId,
            audioFileName: audioFileName,
            audioFileType: audioFileType,
            audioFileSize: audioFileSize,
            audioDurationSeconds: audioDurationSeconds
        )
        let data = try await post(path: "/api/projects/issues", token: token, body: request)
        let wrapper = try await BackgroundJSONDecoder.decode(CreateIssueResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to create issue")
        }
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

    private static func post<T: Encodable>(path: String, token: String, body: T) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw HRConvexAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPError(data: data, response: response, request: request)
        return data
    }

    private static func checkHTTPError(data: Data, response: URLResponse, request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            SessionInvalidationBus.emit(for: request)
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

struct ProjectIssue: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String?
    let title: String?
    let description: String?
    let audioStorageId: String?
    let audioUrl: String?
    let audioDurationMs: Double?
    let status: String?
    let createdAt: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectId
        case title
        case description
        case audioStorageId
        case audioUrl
        case audioDurationMs
        case status
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? UUID().uuidString
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        audioStorageId = try container.decodeIfPresent(String.self, forKey: .audioStorageId)
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl)
        audioDurationMs = try container.decodeFlexibleDouble(forKey: .audioDurationMs)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        createdAt = try container.decodeFlexibleDouble(forKey: .createdAt)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
