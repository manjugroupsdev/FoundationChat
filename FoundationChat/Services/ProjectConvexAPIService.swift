import Foundation

enum ProjectConvexAPIService {
    private static let baseURL = AppConfig.baseURL

    private struct MyProjectsResponse: Decodable {
        let success: Bool
        let projects: [ProjectSummary]?
        let error: String?
    }

    private struct ProjectExpensesResponse: Decodable {
        let success: Bool
        let expenses: [ProjectExpense]?
        let totals: ExpenseTotals?
        let error: String?
    }

    private struct ProjectExpenseResponse: Decodable {
        let success: Bool
        let expense: ProjectExpense?
        let error: String?
    }

    private struct ProjectExpenseMutationResponse: Decodable {
        let success: Bool
        let id: String?
        let error: String?
    }

    struct ExpensesPage: Sendable {
        let expenses: [ProjectExpense]
        let totals: ExpenseTotals
    }

    static func getMyProjects(token: String) async throws -> [ProjectSummary] {
        let data = try await get(path: "/api/projects", token: token)
        let wrapper = try JSONDecoder().decode(MyProjectsResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load projects")
        }
        return wrapper.projects ?? []
    }

    static func listExpenses(
        token: String,
        projectId: String,
        fromDate: String? = nil,
        toDate: String? = nil,
        category: String? = nil
    ) async throws -> ExpensesPage {
        var queryItems = [URLQueryItem(name: "projectId", value: projectId)]
        if let fromDate, !fromDate.isEmpty { queryItems.append(URLQueryItem(name: "fromDate", value: fromDate)) }
        if let toDate, !toDate.isEmpty { queryItems.append(URLQueryItem(name: "toDate", value: toDate)) }
        if let category, !category.isEmpty { queryItems.append(URLQueryItem(name: "category", value: category)) }

        let data = try await get(path: "/api/projects/expenses", token: token, queryItems: queryItems)
        let wrapper = try JSONDecoder().decode(ProjectExpensesResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load expenses")
        }
        return ExpensesPage(expenses: wrapper.expenses ?? [], totals: wrapper.totals ?? .zero)
    }

    static func getExpense(token: String, id: String) async throws -> ProjectExpense {
        let data = try await get(
            path: "/api/projects/expenses/get",
            token: token,
            queryItems: [URLQueryItem(name: "id", value: id)]
        )
        let wrapper = try JSONDecoder().decode(ProjectExpenseResponse.self, from: data)
        guard wrapper.success, let expense = wrapper.expense else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to load expense")
        }
        return expense
    }

    @discardableResult
    static func createExpense(
        token: String,
        projectId: String,
        category: String,
        amount: Double,
        date: String,
        paymentMethod: String?,
        notes: String?,
        receipts: [ExpenseReceipt]? = nil,
        paid: Bool? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "projectId": projectId,
            "category": category,
            "amount": amount,
            "date": date
        ]
        if let paymentMethod, !paymentMethod.isEmpty { body["paymentMethod"] = paymentMethod }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let paid { body["paid"] = paid }
        if let receipts, !receipts.isEmpty { body["receipts"] = receiptPayload(receipts) }

        let data = try await post(path: "/api/projects/expenses/create", token: token, jsonBody: body)
        let wrapper = try JSONDecoder().decode(ProjectExpenseMutationResponse.self, from: data)
        guard wrapper.success, let id = wrapper.id else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to create expense")
        }
        return id
    }

    static func updateExpense(
        token: String,
        id: String,
        category: String?,
        amount: Double?,
        date: String?,
        paymentMethod: String?,
        notes: String?,
        receipts: [ExpenseReceipt]? = nil
    ) async throws {
        var body: [String: Any] = ["id": id]
        if let category, !category.isEmpty { body["category"] = category }
        if let amount { body["amount"] = amount }
        if let date, !date.isEmpty { body["date"] = date }
        if let paymentMethod { body["paymentMethod"] = paymentMethod }
        if let notes { body["notes"] = notes }
        if let receipts { body["receipts"] = receiptPayload(receipts) }

        let data = try await post(path: "/api/projects/expenses/update", token: token, jsonBody: body)
        let wrapper = try JSONDecoder().decode(ProjectExpenseMutationResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update expense")
        }
    }

    static func markExpensePaid(token: String, id: String, paid: Bool) async throws {
        let data = try await post(
            path: "/api/projects/expenses/mark-paid",
            token: token,
            jsonBody: ["id": id, "paid": paid]
        )
        let wrapper = try JSONDecoder().decode(ProjectExpenseMutationResponse.self, from: data)
        guard wrapper.success else {
            throw HRConvexAPIError.server(wrapper.error ?? "Failed to update paid status")
        }
    }

    private static func receiptPayload(_ receipts: [ExpenseReceipt]) -> [[String: Any]] {
        receipts.map { receipt in
            var payload: [String: Any] = ["storageId": receipt.storageId]
            if let url = receipt.url, !url.isEmpty { payload["url"] = url }
            if let name = receipt.name, !name.isEmpty { payload["name"] = name }
            return payload
        }
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
