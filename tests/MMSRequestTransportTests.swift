import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct MMSRequestTransportTests {
    static func main() {
        for method: String? in [nil, "GET", "HEAD", "OPTIONS", "get"] {
            precondition(MMSRequestTransport.session(for: method) === URLSession.shared)
        }
        let writes = MMSRequestTransport.session(for: "POST")
        precondition(writes !== URLSession.shared)
        for method in ["POST", "PUT", "PATCH", "DELETE", "post"] {
            precondition(MMSRequestTransport.session(for: method) === writes)
        }
        precondition(writes.configuration.httpMaximumConnectionsPerHost > 0)
        precondition(MMSRequestTransport.session(for: "GET", path: "/api/hr/shifts/today") === writes)
        precondition(MMSRequestTransport.session(for: "GET", path: "/api/hr/leaves/my") === URLSession.shared)
        print("MMSRequestTransport: 14 assertions passed")
    }
}
