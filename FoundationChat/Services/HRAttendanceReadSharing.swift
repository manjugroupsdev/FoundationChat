import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only concurrent reads are shared. Completed responses are never cached here.
actor HRAttendanceReadSharing {
    static let shared = HRAttendanceReadSharing()
    private struct Entry {
        let generation: UInt
        let task: Task<Data, Error>
    }
    private var generation: UInt = 0
    private var inFlight: [String: Entry] = [:]

    nonisolated static func key(for request: URLRequest) -> String? {
        guard request.httpMethod == nil || request.httpMethod == "GET",
              let url = request.url,
              ["/api/hr/attendance/today", "/api/hr/attendance/day-sessions",
               "/api/hr/attendance/my"].contains(url.path),
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              !authorization.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // Query dictionaries can generate a different order for the same range.
        // Repeated query keys are left in order because their order may matter.
        if let items = components.queryItems, Set(items.map(\.name)).count == items.count {
            components.queryItems = items.sorted { $0.name < $1.name }
        }
        guard let canonicalURL = components.string else { return nil }
        return authorization + "|" + canonicalURL + "|" + String(request.timeoutInterval)
    }

    func data(key: String, fetch: @escaping @Sendable () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        let expected = generation
        if let existing = inFlight[key] {
            let data = try await existing.task.value
            try Task.checkCancellation()
            guard expected == generation else { throw CancellationError() }
            return data
        }
        let task = Task<Data, Error> { try await fetch() }
        inFlight[key] = Entry(generation: expected, task: task)
        defer {
            if inFlight[key]?.generation == expected { inFlight[key] = nil }
        }
        let data = try await task.value
        try Task.checkCancellation()
        guard expected == generation else { throw CancellationError() }
        return data
    }

    /// A read started before a punch must not overwrite the post-punch refresh.
    func invalidate() {
        generation &+= 1
        inFlight.removeAll()
    }
}

enum HRRefreshPolicy {
    nonisolated static let intervalNanoseconds: UInt64 = 180_000_000_000

    nonisolated static func canRefresh(isSelected: Bool, isForeground: Bool, isPunchPresented: Bool) -> Bool {
        isSelected && isForeground && !isPunchPresented
    }
}
