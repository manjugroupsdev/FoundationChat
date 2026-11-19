import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct HRAttendanceReadSharingTests {
    actor Probe {
        private(set) var calls = 0
        func fetch() -> Data { calls += 1; return Data([UInt8(calls)]) }
    }
    actor Latch {
        private var continuation: CheckedContinuation<Data, Error>?
        private var started = false
        func fetch() async throws -> Data {
            started = true
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func waitUntilStarted() async {
            while !started { await Task.yield() }
        }
        func release() { continuation?.resume(returning: Data([7])); continuation = nil }
    }
    enum Failure: Error { case expected }
    static func request(_ path: String, token: String = "test-token") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://attendance.example" + path)!)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }

    static func main() async throws {
        precondition(HRAttendanceReadSharing.key(for: request("/api/hr/attendance/today")) != nil)
        precondition(HRAttendanceReadSharing.key(for: request("/api/hr/attendance/my?fromDate=2026-11-01&toDate=2026-11-19")) != nil,
                     "Monthly attendance must share overlapping reads")
        let range = "/api/hr/attendance/my?fromDate=2026-11-01&toDate=2026-11-19"
        let key = HRAttendanceReadSharing.key(for: request(range))!
        precondition(key == HRAttendanceReadSharing.key(for: request("/api/hr/attendance/my?toDate=2026-11-19&fromDate=2026-11-01")))
        precondition(key != HRAttendanceReadSharing.key(for: request(range, token: "other")))
        precondition(key != HRAttendanceReadSharing.key(for: request(range + "&staffId=other")))
        precondition(key != HRAttendanceReadSharing.key(for: request(range + "&cursor=next")))
        precondition(key != HRAttendanceReadSharing.key(for: request(range + "&status=absent")))
        precondition(HRAttendanceReadSharing.key(for: request("/api/hr/attendance/today-extra")) == nil)
        precondition(HRAttendanceReadSharing.key(for: request("/api/chat/typing")) == nil)
        var write = request("/api/hr/attendance/today")
        write.httpMethod = "POST"
        precondition(HRAttendanceReadSharing.key(for: write) == nil)
        var anonymous = request("/api/hr/attendance/today")
        anonymous.setValue(nil, forHTTPHeaderField: "Authorization")
        precondition(HRAttendanceReadSharing.key(for: anonymous) == nil)
        var deadline = request(range)
        deadline.timeoutInterval = 15
        precondition(key != HRAttendanceReadSharing.key(for: deadline))
        precondition(HRRefreshPolicy.intervalNanoseconds == 180_000_000_000)
        for selected in [false, true] {
            for foreground in [false, true] {
                for punching in [false, true] {
                    precondition(HRRefreshPolicy.canRefresh(isSelected: selected, isForeground: foreground, isPunchPresented: punching)
                                 == (selected && foreground && !punching))
                }
            }
        }
        let reads = HRAttendanceReadSharing()
        let probe = Probe()
        let first = try await reads.data(key: key) { await probe.fetch() }
        let second = try await reads.data(key: key) { await probe.fetch() }
        precondition(first != second, "Completed reads must never be cached")
        do {
            _ = try await reads.data(key: "failure") { throw Failure.expected }
            preconditionFailure("Expected failure")
        } catch Failure.expected {}
        let recovered = try await reads.data(key: "failure") { Data([3]) }
        precondition(recovered == Data([3]))

        let latch = Latch()
        let oldRead = Task { try await reads.data(key: "punch") { try await latch.fetch() } }
        await latch.waitUntilStarted()
        await reads.invalidate()
        let freshRead = try await reads.data(key: "punch") { Data([9]) }
        await latch.release()
        do { _ = try await oldRead.value; preconditionFailure("Pre-punch result must be discarded") }
        catch is CancellationError {}
        precondition(freshRead == Data([9]))

        let coalesced = HRAttendanceReadSharing()
        let slow = Latch()
        let owner = Task { try await coalesced.data(key: "same") { try await slow.fetch() } }
        await slow.waitUntilStarted()
        let release = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            await slow.release()
        }
        let joined = try await coalesced.data(key: "same") { preconditionFailure("Duplicate network fetch") }
        let owned = try await owner.value
        _ = try await release.value
        precondition(joined == owned)
        print("Attendance sharing and lifecycle: 26 checks passed")
    }
}
