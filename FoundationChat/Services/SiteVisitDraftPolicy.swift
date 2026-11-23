import Foundation

enum SiteVisitDraftPolicy {
    static func leadIdentity(id: String?, coreLeadId: String?) -> (leadId: String?, coreLeadId: String?) {
        let raw = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = coreLeadId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCore = raw?.range(of: "^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$", options: [.regularExpression, .caseInsensitive]) != nil
        return (isCore || raw?.isEmpty != false ? nil : raw,
                core?.isEmpty == false ? core : (isCore ? raw : nil))
    }

    static func lookupMatches(requestedPhone: String, currentPhone: String) -> Bool {
        requestedPhone.count == 10 && requestedPhone == currentPhone
    }

    static func usableCoordinates(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return abs(latitude) >= 0.000001 || abs(longitude) >= 0.000001
    }

    static func hasRequiredVisitor(routing: String, names: [String]) -> Bool {
        guard routing == "out_of_station" || routing == "immediate_pickup" else { return true }
        return names.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func fingerprint(encodedRequest: Data) throws -> Data {
        guard var body = try JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        body.removeValue(forKey: "requestId")
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

struct SiteVisitOutcomeReceipt: Decodable, Sendable {
    struct Visit: Decodable, Sendable {
        let status: String?
        let outcome: String?
        let proposedSiteVisit: SavedState?
    }

    struct SavedState: Decodable, Sendable {
        let status: String?
        let outcome: String?
    }

    let success: Bool
    let error: String?
    let visit: Visit?
    let status: String?
    let outcome: String?

    func confirms(_ requestedOutcome: String) -> Bool {
        guard success else { return false }
        let state = visit?.proposedSiteVisit
        let savedStatus = normalized(state?.status ?? visit?.status ?? status)
        let savedOutcome = normalized(state?.outcome ?? visit?.outcome ?? outcome)
        return ["completed", "complete", "done", "closed"].contains(savedStatus)
            && savedOutcome == normalized(requestedOutcome)
            && !savedOutcome.isEmpty
    }

    private func normalized(_ value: String?) -> String {
        let value = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        return value == "postponed" ? "follow_up" : value
    }
}
