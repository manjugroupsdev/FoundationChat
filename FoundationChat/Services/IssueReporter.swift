import Foundation
import MetricKit
import Network
import UIKit

/// Existing app hooks, direct to PostHog; no MMS telemetry requests or remote configuration.
nonisolated final class IssueReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = IssueReporter()
    private let queue = DispatchQueue(label: "mobile-posthog", qos: .utility)
    private let ingress = DispatchSemaphore(value: 64)
    private let monitor = NWPathMonitor()
    private var items: [[String: Any]] = []
    private var budget = MobileTelemetryBudget()
    private var loaded = false
    private var started = false
    private var scheduled = false
    private var sending = false
    private var online = false
    private var retryAt: TimeInterval = 0
    private var lastAttempt: TimeInterval = -60
    private var failures = 0
    private var anonymousID = ""
    private let defaults = UserDefaults.standard
    private static let authority = URL(string: AppConfig.baseURL)?.host
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    private static let iso = ISO8601DateFormatter()
    private let session = MobileTelemetryTransport.session()
    private var queueURL: URL { Self.directory.appendingPathComponent("mobile_posthog_queue_v1.json") }
    private static var crashURL: URL { directory.appendingPathComponent("mobile_posthog_crash_v1.json") }
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func start() {
        guard MobilePostHogConfig.enabled else { return }
        submit { [self] in
            guard !started else { return }
            started = true
            load()
            // Legacy reports contain raw server/user text; never forward those to PostHog.
            for name in ["mobile_issue_queue.json", "mobile_issue_crash.json"] {
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(name))
            }
            if let data = try? Data(contentsOf: Self.crashURL),
               let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                add(report, timing: false, healthy: false)
                try? FileManager.default.removeItem(at: Self.crashURL)
            }
            monitor.pathUpdateHandler = { [weak self] path in
                self?.submit { [weak self] in
                    guard let self else { return }
                    self.online = path.status == .satisfied
                    if self.online { self.schedule() }
                }
            }
            monitor.start(queue: queue)
            MXMetricManager.shared.add(self)
            NSSetUncaughtExceptionHandler(mobileTelemetryExceptionHandler)
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: nil) { [weak self] _ in
                    guard let reporter = self else { return }
                    reporter.submit { reporter.schedule() }
                }
            schedule()
        }
    }

    // Arbitrary call-site breadcrumbs can include personal text. Do not retain them.
    func crumb(_ text: String) {}

    /// Observes the original request once; returns/rethrows exactly the original result.
    static func data(for request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        guard MobilePostHogConfig.enabled,
              let service = MobileTelemetryPolicy.service(request.url?.host, authority: authority),
              request.url?.path.hasPrefix("/api/mobile/issues/") != true else {
            return try await session.data(for: request)
        }
        let start = ProcessInfo.processInfo.systemUptime
        do {
            let result = try await session.data(for: request)
            if let response = result.1 as? HTTPURLResponse {
                shared.observe(request, service: service, status: response.statusCode,
                    duration: ProcessInfo.processInfo.systemUptime - start, error: nil)
            }
            return result
        } catch {
            let urlError = error as? URLError
            if !(error is CancellationError), urlError?.code != .cancelled,
               urlError?.code != .notConnectedToInternet {
                let type: String
                switch urlError?.code {
                case .timedOut: type = "Timeout"
                case .cannotFindHost, .dnsLookupFailed: type = "DNS"
                case .secureConnectionFailed, .serverCertificateUntrusted: type = "TLS"
                default: type = "Connection"
                }
                shared.observe(request, service: service, status: 0,
                    duration: ProcessInfo.processInfo.systemUptime - start, error: type)
            }
            throw error
        }
    }

    private func observe(_ request: URLRequest, service: String, status: Int, duration: Double, error: String?) {
        let endpoint = "\(MobileTelemetryPolicy.method(request.httpMethod)) \(MobileTelemetryPolicy.route(request.url?.path ?? ""))"
        let timing = (200..<400).contains(status)
        let healthy = timing && duration < 3
        let properties: [String: Any] = ["service": service, "endpoint": endpoint,
            "method": MobileTelemetryPolicy.method(request.httpMethod), "status": status,
            "duration_ms": Int(min(300, max(0, duration)) * 1000),
            "outcome": error ?? (status >= 400 ? "http_error" : healthy ? "success" : "slow"),
            "sample_rate": healthy ? 0.05 : 1.0]
        let signature = "\(service) \(endpoint) \(error ?? String(status))"
        submit { [self] in
            if error != nil && !online { return }
            let report = Self.event("mobile_endpoint",
                properties: properties, signature: signature)
            add(report, timing: timing, healthy: healthy)
        }
    }

    func onNotice(_ text: String, kind: Floater.Kind, file: String) {
        guard kind == .error else { return }
        let screen = Self.screenName(fromFile: file)
        submit { [self] in
            var report = Self.event("$exception", properties: ["screen": screen], signature: "flow \(screen)")
            Self.exception(&report, type: "MobileFlowError", handled: true)
            add(report, timing: false, healthy: false)
        }
    }
    static func screenName(fromFile file: String) -> String {
        MobileTelemetryPolicy.symbol(((file as NSString).lastPathComponent as NSString).deletingPathExtension)
    }

    private static func event(_ name: String, properties: [String: Any], signature: String) -> [String: Any] {
        ["event": name, "properties": properties, "fingerprint": signature,
         "occurredAt": Date().timeIntervalSince1970, "uuid": UUID().uuidString]
    }
    private static func exception(_ report: inout [String: Any], type: String, handled: Bool) {
        var properties = report["properties"] as? [String: Any] ?? [:]
        properties["$exception_list"] = [["type": type, "value": type,
            "mechanism": ["type": "mobile", "handled": handled, "synthetic": true]]]
        properties["$exception_fingerprint"] = report["fingerprint"]
        report["properties"] = properties
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // MetricKit delivers native crash diagnostics later. No raw reason/stack JSON or memory data.
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let code = "NativeCrash_\(crash.exceptionType?.intValue ?? 0)_\(crash.signal?.intValue ?? 0)"
                let crashBuild = crash.metaData.applicationBuildVersion
                submit { [self] in
                    var report = Self.event("$exception", properties: ["crash_build": MobileTelemetryPolicy.symbol("b" + crashBuild)],
                        signature: "crash \(code) b\(MobileTelemetryPolicy.symbol(crashBuild))")
                    Self.exception(&report, type: code, handled: false)
                    add(report, timing: false, healthy: false)
                }
            }
        }
    }

    fileprivate static func saveException(_ error: NSException) {
        let type = MobileTelemetryPolicy.symbol(error.name.rawValue)
        var report = event("$exception", properties: [:], signature: "crash \(type)")
        exception(&report, type: type, handled: false)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: report) { try? data.write(to: crashURL, options: .atomic) }
    }

    private func submit(_ work: @escaping @Sendable () -> Void) {
        guard MobilePostHogConfig.enabled, ingress.wait(timeout: .now()) == .success else { return }
        queue.async { [self] in defer { ingress.signal() }; work() }
    }
    private func load() {
        guard !loaded else { return }
        loaded = true
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        anonymousID = defaults.string(forKey: "posthog.anonymousID") ?? UUID().uuidString
        defaults.set(anonymousID, forKey: "posthog.anonymousID")
        budget = MobileTelemetryBudget(day: defaults.object(forKey: "posthog.day") as? Int ?? -1,
            errors: defaults.integer(forKey: "posthog.errors"), timings: defaults.integer(forKey: "posthog.timings"),
            exceptions: defaults.integer(forKey: "posthog.exceptions"))
        retryAt = defaults.double(forKey: "posthog.retryAt")
        if let data = try? Data(contentsOf: queueURL), data.count <= 512_000,
           let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            items = Array(saved.filter {
                let age = Date().timeIntervalSince1970 - ($0["occurredAt"] as? Double ?? 0)
                return age >= 0 && age <= MobileTelemetryPolicy.maxAge
            }.prefix(MobileTelemetryPolicy.maxQueue))
        }
    }
    private func add(_ report: [String: Any], timing: Bool, healthy: Bool) {
        load()
        guard let signature = report["fingerprint"] as? String,
              !items.contains(where: { $0["fingerprint"] as? String == signature }),
              budget.accept(signature, timing: timing, healthy: healthy, now: Date().timeIntervalSince1970,
                  exception: report["event"] as? String == "$exception") else { return }
        defaults.set(budget.day, forKey: "posthog.day")
        defaults.set(budget.errors, forKey: "posthog.errors")
        defaults.set(budget.timings, forKey: "posthog.timings")
        defaults.set(budget.exceptions, forKey: "posthog.exceptions")
        if items.count >= MobileTelemetryPolicy.maxQueue { items.removeFirst() }
        items.append(report)
        persist()
        schedule()
    }
    private func persist() {
        if let data = try? JSONSerialization.data(withJSONObject: items) { try? data.write(to: queueURL, options: .atomic) }
    }
    private func schedule() {
        guard !scheduled, !sending, !items.isEmpty else { return }
        scheduled = true
        let delay = max(MobileTelemetryPolicy.flushInterval, retryAt - Date().timeIntervalSince1970,
            lastAttempt + MobileTelemetryPolicy.flushInterval - ProcessInfo.processInfo.systemUptime)
        queue.asyncAfter(deadline: .now() + delay) { [self] in scheduled = false; send() }
    }
    private func send() {
        items.removeAll { Date().timeIntervalSince1970 - ($0["occurredAt"] as? Double ?? 0) > MobileTelemetryPolicy.maxAge }
        guard !sending, online, !items.isEmpty, Date().timeIntervalSince1970 >= retryAt else { return }
        let batch = Array(items.prefix(MobileTelemetryPolicy.batchSize))
        let events: [[String: Any]] = batch.map { stored in
            var properties = stored["properties"] as? [String: Any] ?? [:]
            properties["$process_person_profile"] = false
            properties["$geoip_disable"] = true
            properties["platform"] = "ios"
            properties["build"] = Self.build
            properties["app_version"] = Self.version
            properties["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
            return ["event": stored["event"] ?? "mobile_endpoint", "properties": properties,
                "distinct_id": anonymousID, "uuid": stored["uuid"] ?? UUID().uuidString,
                "timestamp": Self.iso.string(from: Date(timeIntervalSince1970: stored["occurredAt"] as? Double ?? 0))]
        }
        guard let request = try? MobileTelemetryTransport.request(events: events) else { return }
        sending = true
        lastAttempt = ProcessInfo.processInfo.systemUptime
        let ids = Set(batch.compactMap { $0["uuid"] as? String })
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let http = response as? HTTPURLResponse
            // Completion cannot be dropped by the bounded observation ingress.
            self.queue.async {
                self.sending = false
                let ok = error == nil && http.map { (200..<300).contains($0.statusCode) } == true
                if ok {
                    self.items.removeAll { ids.contains($0["uuid"] as? String ?? "") }
                    self.failures = 0; self.retryAt = 0
                    self.persist()
                } else {
                    self.failures += 1
                    self.retryAt = Date().timeIntervalSince1970 + MobileTelemetryPolicy.retryDelay(status: http?.statusCode,
                        failures: self.failures, retryAfter: http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
                }
                self.defaults.set(self.retryAt, forKey: "posthog.retryAt")
                // Failures wait for a real event/resume; no recurring background polling.
                if ok { self.schedule() }
            }
        }.resume()
    }
}

nonisolated private func mobileTelemetryExceptionHandler(_ exception: NSException) {
    IssueReporter.saveException(exception)
}
