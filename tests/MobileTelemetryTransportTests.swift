import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct MobileTelemetryTransportTests {
    static func main() throws {
        let config = MobileTelemetryTransport.configuration()
        precondition(config.httpCookieStorage == nil && config.urlCredentialStorage == nil && config.urlCache == nil)
        precondition(config.timeoutIntervalForRequest == 10 && config.timeoutIntervalForResource == 15)
        precondition(config.httpMaximumConnectionsPerHost == 1)
        let properties: [String: Any] = ["$process_person_profile": false, "$geoip_disable": true,
            "endpoint": "POST /api/hr/attendance/punch-in", "status": 503, "duration_ms": 1200]
        let event: [String: Any] = ["event": "mobile_endpoint", "distinct_id": "synthetic-non-user", "properties": properties]
        let request = try MobileTelemetryTransport.request(events: [event])
        precondition(request.url?.absoluteString == "https://us.i.posthog.com/batch/" && request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
        precondition(request.value(forHTTPHeaderField: "X-App-Build") == nil)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["api_key"] as? String == MobilePostHogConfig.projectToken)
        let sent = (body["batch"] as! [[String: Any]])[0]
        precondition(sent["event"] as? String == "mobile_endpoint")
        let sentProperties = sent["properties"] as! [String: Any]
        precondition(sentProperties["$process_person_profile"] as? Bool == false)
        precondition(sentProperties["$geoip_disable"] as? Bool == true)
        print("Mobile PostHog isolated transport/configuration and request schema: passed")
    }
}
