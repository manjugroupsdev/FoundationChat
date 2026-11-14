import Foundation
import MetricKit
import Network
import UIKit

/// Reports what goes wrong on the phone to Settings → Mobile → Issues (same
/// as Android's IssueReporter), so a failure is known without the staff
/// member having to describe it:
///
/// - crash: from MetricKit's crash diagnostics (delivered on a later launch)
///   and uncaught Objective-C exceptions (saved at crash time);
/// - http: a server call that failed (4xx except 401, 5xx) with the reply;
/// - network: a call that timed out / couldn't connect while the phone had
///   internet (nothing is reported when the phone is simply offline);
/// - flow: an error notice the user saw (Floater) — attached to the call that
///   caused it when there is one, otherwise reported on its own.
///
/// Reports carry the screen, the last steps (calls made, notices shown),
/// build, phone model and network type, wait in a small file queue and go
/// out in batches. The same problem within 10 minutes is counted, not sent
/// again. Request bodies and query values are never sent.
nonisolated final class IssueReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = IssueReporter()

    private let queue = DispatchQueue(label: "issue-reporter")
    private var items: [[String: Any]] = []
    private var crumbs: [String] = []
    private var lastSentAt: [String: Date] = [:]
    private var loaded = false
    private var retryAfter = Date.distantPast
    private var sendScheduled = false
    private var started = false
    private var online = true
    private var networkType = "unknown"
    private let pathMonitor = NWPathMonitor()
    private var lastScreen = "App"

    private let maxQueue = 60
    private let maxCrumbs = 30
    private let repeatWindow: TimeInterval = 10 * 60
    private let linkWindow: TimeInterval = 6
    private let reportPath = "/api/mobile/issues/"

    private static let deviceModel: String = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.isEmpty ? "iPhone" : machine
    }()
    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    private static var osVersionText: String {
        "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    }
    private static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    private static let buildNumber = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

    private var queueURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mobile_issue_queue.json")
    }
    fileprivate static var crashURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("mobile_issue_crash.json")
    }

    /// Call once at launch.
    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            loadQueue()
            promoteSavedCrash()
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.queue.async {
                self.online = path.status == .satisfied
                self.networkType = path.status != .satisfied ? "offline"
                    : path.usesInterfaceType(.wifi) ? "wifi"
                    : path.usesInterfaceType(.cellular) ? "mobile data"
                    : "other"
                if self.online && !self.items.isEmpty { self.scheduleSend(after: 3) }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "issue-reporter-path"))
        MXMetricManager.shared.add(self)
        NSSetUncaughtExceptionHandler(issueReporterExceptionHandler)
        scheduleSend(after: 5)
    }

    // MARK: Breadcrumbs

    func crumb(_ text: String) {
        let stamp = Self.clock.string(from: Date())
        queue.async { [self] in
            crumbs.append(String("\(stamp) \(text)".prefix(200)))
            if crumbs.count > maxCrumbs { crumbs.removeFirst(crumbs.count - maxCrumbs) }
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: HTTP

    /// Drop-in for `URLSession.shared.data(for:)`: same result, and failures
    /// are reported.
    static func data(for request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        if path.hasPrefix(shared.reportPath) { return try await session.data(for: request) }
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            shared.observe(request: request, response: response, data: data, started: started)
            return (data, response)
        } catch {
            shared.observe(request: request, error: error, started: started)
            throw error
        }
    }

    private func observe(request: URLRequest, response: URLResponse, data: Data, started: Date) {
        guard let http = response as? HTTPURLResponse else { return }
        let took = Int(Date().timeIntervalSince(started) * 1000)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        crumb("\(method) \(path) → \(http.statusCode) (\(took) ms)")
        guard http.statusCode >= 400, http.statusCode != 401 else { return }
        let endpoint = "\(method) \(Self.normalizedPath(path))"
        let body = String(data: data.prefix(4096), encoding: .utf8) ?? ""
        let serverText = FloaterText.notice(for: body)?.text ?? FloaterText.forStatus(http.statusCode).text
        enqueue([
            "kind": "http",
            "fingerprint": "\(endpoint) \(http.statusCode)",
            "title": "\(endpoint) → HTTP \(http.statusCode)",
            "message": String("HTTP \(http.statusCode) \(serverText)".prefix(2000)),
            "errorCode": "HTTP \(http.statusCode)",
            "endpoint": endpoint,
            "requestMethod": method,
            "requestUrl": Self.safeURL(request.url),
            "responseStatus": http.statusCode,
            "durationMs": took,
            "responseBody": String(body.prefix(3000)),
        ])
    }

    private func observe(request: URLRequest, error: Error, started: Date) {
        let took = Int(Date().timeIntervalSince(started) * 1000)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let urlError = error as? URLError
        let errorType = urlError.map { "URLError.\($0.code.rawValue)" } ?? String(describing: Swift.type(of: error))
        crumb("\(method) \(path) → \(errorType) (\(took) ms)")
        if error is CancellationError || urlError?.code == .cancelled { return }
        let endpoint = "\(method) \(Self.normalizedPath(path))"
        let description = error.localizedDescription
        queue.async { [self] in
            // Phone offline: not an app problem.
            guard online, urlError?.code != .notConnectedToInternet else { return }
            enqueueOnQueue([
                "kind": "network",
                "fingerprint": "\(endpoint) \(errorType)",
                "title": "\(endpoint) → \(Self.describe(urlError) ?? errorType)",
                "message": String("\(errorType): \(description)".prefix(2000)),
                "errorCode": errorType,
                "endpoint": endpoint,
                "requestMethod": method,
                "requestUrl": Self.safeURL(request.url),
                "durationMs": took,
            ])
        }
    }

    private static func describe(_ error: URLError?) -> String? {
        guard let error else { return nil }
        switch error.code {
        case .timedOut: return "timed out"
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: return "couldn't connect"
        case .networkConnectionLost: return "connection lost"
        case .secureConnectionFailed: return "secure connection failed"
        default: return nil
        }
    }

    /// Scheme, host and path; query keys only (values can be phones/OTPs).
    private static func safeURL(_ url: URL?) -> String {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        let base = "\(components.scheme ?? "https")://\(components.host ?? "")\(components.path)"
        let keys = components.queryItems?.map(\.name) ?? []
        return keys.isEmpty ? base : base + "?" + keys.map { "\($0)=…" }.joined(separator: "&")
    }

    /// /api/x/k97mw73m5j81reyfb2kvqz8hc98ey4jh → /api/x/:id so repeats group.
    private static func normalizedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).map { segment -> String in
            if segment.count >= 16, segment.contains(where: \.isNumber) { return ":id" }
            if !segment.isEmpty, segment.allSatisfy(\.isNumber) { return ":n" }
            return String(segment)
        }.joined(separator: "/")
    }

    // MARK: Notices the user saw

    /// From Floater: an error the user was shown is a flow that didn't finish.
    func onNotice(_ text: String, kind: Floater.Kind, file: String) {
        let screen = Self.screenName(fromFile: file)
        crumb("Notice (\(kind)) on \(screen): \(text)")
        queue.async { [self] in
            lastScreen = screen
            let now = Date().timeIntervalSince1970 * 1000
            if let index = items.lastIndex(where: {
                let kind = $0["kind"] as? String
                let at = $0["occurredAt"] as? Double ?? 0
                return (kind == "http" || kind == "network") && now - at <= linkWindow * 1000 && $0["userMessage"] == nil
            }) {
                items[index]["userMessage"] = String(text.prefix(500))
                items[index]["flow"] = screen
                if items[index]["screen"] as? String == "App" { items[index]["screen"] = screen }
                persist()
                return
            }
            guard kind == .error else { return }
            let pattern = text.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression).prefix(120)
            enqueueOnQueue([
                "kind": "flow",
                "fingerprint": "flow \(screen) \(pattern)",
                "title": String("\(screen): \(text.prefix(140))"),
                "message": String(text.prefix(2000)),
                "userMessage": String(text.prefix(500)),
                "errorCode": "Flow failed",
                "screen": screen,
                "flow": screen,
            ])
        }
    }

    /// "FoundationChat/Views/Marketing/CpVisitsView.swift" → "CpVisitsView".
    static func screenName(fromFile file: String) -> String {
        let name = (file as NSString).lastPathComponent
        return name.hasSuffix(".swift") ? String(name.dropLast(6)) : (name.isEmpty ? "App" : name)
    }

    // MARK: Crashes

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let exception = crash.exceptionType.map { "EXC \($0)" }
                let signal = crash.signal.map { "SIG \($0)" }
                let reason = crash.terminationReason ?? crash.virtualMemoryRegionInfo ?? ""
                let code = [exception, signal].compactMap { $0 }.joined(separator: " · ")
                let stack = String(data: crash.callStackTree.jsonRepresentation(), encoding: .utf8) ?? ""
                let build = Int(crash.metaData.applicationBuildVersion) ?? Self.buildNumber
                queue.async { [self] in
                    enqueueOnQueue([
                        "kind": "crash",
                        "fingerprint": "crash \(code) \(reason.prefix(80)) b\(build)",
                        "title": "Crash: \(code.isEmpty ? "unknown" : code)\(reason.isEmpty ? "" : " — \(reason.prefix(100))")",
                        "message": "Crash \(code) in build \(build). \(reason)",
                        "errorCode": code.isEmpty ? "Crash" : code,
                        "screen": "Previous run",
                        "stack": String(stack.prefix(12_000)),
                        "occurredAt": payload.timeStampEnd.timeIntervalSince1970 * 1000,
                    ], breadcrumbs: false)
                }
            }
        }
    }

    fileprivate func saveException(_ exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")
        let type = exception.name.rawValue
        let frame = exception.callStackSymbols.first(where: { $0.contains("FoundationChat") }) ?? ""
        let report: [String: Any] = [
            "kind": "crash",
            "fingerprint": "crash \(type) \(frame.suffix(80))",
            "title": "Crash: \(type)",
            "message": "\(type): \(exception.reason ?? "")",
            "errorCode": type,
            "screen": lastScreen,
            "stack": String(stack.prefix(12_000)),
            "occurredAt": Date().timeIntervalSince1970 * 1000,
            "breadcrumbs": crumbs,
            "count": 1,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: Self.crashURL)
        }
    }

    private func promoteSavedCrash() {
        guard let data = try? Data(contentsOf: Self.crashURL),
              let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: Self.crashURL)
        add(report)
        persist()
    }

    // MARK: Queue (runs on `queue`)

    private func enqueue(_ report: [String: Any]) {
        queue.async { [self] in enqueueOnQueue(report) }
    }

    private func enqueueOnQueue(_ report: [String: Any], breadcrumbs: Bool = true) {
        loadQueue()
        var full = report
        if full["occurredAt"] == nil { full["occurredAt"] = Date().timeIntervalSince1970 * 1000 }
        if full["screen"] == nil { full["screen"] = lastScreen }
        if breadcrumbs { full["breadcrumbs"] = crumbs }
        full["count"] = 1
        add(full)
        persist()
        scheduleSend(after: 8)
    }

    private func add(_ report: [String: Any]) {
        guard let fingerprint = report["fingerprint"] as? String else { return }
        if let index = items.firstIndex(where: { $0["fingerprint"] as? String == fingerprint }) {
            items[index]["count"] = (items[index]["count"] as? Int ?? 1) + 1
            return
        }
        if let sent = lastSentAt[fingerprint], Date().timeIntervalSince(sent) < repeatWindow { return }
        items.append(report)
        if items.count > maxQueue { items.removeFirst(items.count - maxQueue) }
    }

    private func loadQueue() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: queueURL),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let cutoff = (Date().timeIntervalSince1970 - 3 * 24 * 3600) * 1000
        items = saved.filter { ($0["occurredAt"] as? Double ?? 0) >= cutoff }
    }

    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: items) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }

    private func scheduleSend(after seconds: Double) {
        queue.async { [self] in
            guard !sendScheduled else { return }
            sendScheduled = true
            queue.asyncAfter(deadline: .now() + seconds) { [self] in
                sendScheduled = false
                send()
            }
        }
    }

    private func send() {
        loadQueue()
        guard online, Date() >= retryAfter, !items.isEmpty,
              let url = URL(string: AppConfig.baseURL + reportPath + "report") else { return }
        let batch = Array(items.prefix(20))
        let body: [String: Any] = [
            "platform": "ios",
            "appVersion": Self.appVersion,
            "buildNumber": Self.buildNumber,
            "deviceModel": Self.deviceModel,
            "osVersion": Self.osVersionText,
            "networkType": networkType,
            "reports": batch,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = try? KeychainTokenStore().load()?.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = payload
        let sentFingerprints = Set(batch.compactMap { $0["fingerprint"] as? String })
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            self.queue.async {
                if ok {
                    let now = Date()
                    sentFingerprints.forEach { self.lastSentAt[$0] = now }
                    self.items.removeAll { sentFingerprints.contains($0["fingerprint"] as? String ?? "") }
                    self.persist()
                    self.retryAfter = .distantPast
                    if !self.items.isEmpty { self.scheduleSend(after: 2) }
                } else {
                    // Server down or route not live yet: keep the queue, retry later.
                    self.retryAfter = Date().addingTimeInterval(self.repeatWindow)
                }
            }
        }.resume()
    }
}

nonisolated private func issueReporterExceptionHandler(_ exception: NSException) {
    IssueReporter.shared.saveException(exception)
}
