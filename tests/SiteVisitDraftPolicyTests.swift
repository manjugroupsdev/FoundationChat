import Foundation

@main
struct SiteVisitDraftPolicyTests {
    static func main() throws {
        func check(_ value: Bool) { precondition(value) }
        precondition(SiteVisitDraftPolicy.lookupMatches(requestedPhone: "9000000001", currentPhone: "9000000001"))
        precondition(!SiteVisitDraftPolicy.lookupMatches(requestedPhone: "9000000001", currentPhone: "9000000002"))
        precondition(!SiteVisitDraftPolicy.lookupMatches(requestedPhone: "9000000001", currentPhone: "900000000"))
        precondition(SiteVisitDraftPolicy.usableCoordinates(latitude: 0, longitude: 80))
        precondition(SiteVisitDraftPolicy.usableCoordinates(latitude: 12, longitude: 0))
        precondition(!SiteVisitDraftPolicy.usableCoordinates(latitude: 0, longitude: 0))
        precondition(!SiteVisitDraftPolicy.usableCoordinates(latitude: .nan, longitude: 80))
        precondition(!SiteVisitDraftPolicy.usableCoordinates(latitude: 91, longitude: 80))
        precondition(!SiteVisitDraftPolicy.hasRequiredVisitor(routing: "out_of_station", names: [" "]))
        precondition(SiteVisitDraftPolicy.hasRequiredVisitor(routing: "immediate_pickup", names: ["Test client"]))
        precondition(SiteVisitDraftPolicy.hasRequiredVisitor(routing: "direct_sv", names: []))

        let first = Data(#"{"requestId":"one","routing":"same_area","attendees":[{"name":"Test"}]}"#.utf8)
        let retry = Data(#"{"attendees":[{"name":"Test"}],"routing":"same_area","requestId":"two"}"#.utf8)
        let changed = Data(#"{"requestId":"one","routing":"out_of_station","attendees":[{"name":"Test"}]}"#.utf8)
        check(try SiteVisitDraftPolicy.fingerprint(encodedRequest: first) == SiteVisitDraftPolicy.fingerprint(encodedRequest: retry))
        check(try SiteVisitDraftPolicy.fingerprint(encodedRequest: first) != SiteVisitDraftPolicy.fingerprint(encodedRequest: changed))
        let core = "7b76f254-b620-4bdd-89de-a6de3b61d769"
        precondition(SiteVisitDraftPolicy.leadIdentity(id: core, coreLeadId: nil).leadId == nil)
        precondition(SiteVisitDraftPolicy.leadIdentity(id: core, coreLeadId: nil).coreLeadId == core)
        precondition(SiteVisitDraftPolicy.leadIdentity(id: "legacy", coreLeadId: core).leadId == "legacy")
        precondition(SiteVisitStaffRules.salesMarketing(status: "active", department: nil, designation: "Sales and Marketing Manager"))
        precondition(!SiteVisitStaffRules.salesMarketing(status: "inactive", department: nil, designation: "Sales and Marketing Manager"))

        let decoder = JSONDecoder()
        func receipt(_ json: String) throws -> SiteVisitOutcomeReceipt {
            try decoder.decode(SiteVisitOutcomeReceipt.self, from: Data(json.utf8))
        }
        check(try receipt(#"{"success":true,"visit":{"status":"completed","outcome":"follow_up"}}"#).confirms("postponed"))
        check(try receipt(#"{"success":true,"visit":{"status":"completed","outcome":"postponed"}}"#).confirms("follow_up"))
        check(try !receipt(#"{"success":true}"#).confirms("interested"))
        check(try !receipt(#"{"success":false,"visit":{"status":"completed","outcome":"interested"}}"#).confirms("interested"))
        check(try !receipt(#"{"success":true,"visit":{"status":"on_counselling","outcome":"interested"}}"#).confirms("interested"))
        check(try !receipt(#"{"success":true,"visit":{"status":"completed","outcome":"other"}}"#).confirms("interested"))
        print("SiteVisitDraftPolicyTests passed")
    }
}
