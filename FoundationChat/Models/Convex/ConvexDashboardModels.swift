import Foundation

/// Company-wide Home dashboard payload used by Android `MobileDashboardResponse`.
struct ConvexMobileDashboard: Decodable, Equatable, Sendable {
    let success: Bool
    let date: String?
    let totalCalls: Int
    let incomingCalls: Int
    let outboundCalls: Int
    let hot: Int
    let warm: Int
    let cold: Int
    let cpVisitsFixed: Int
    let svVisitsFixed: Int
    let totalStaff: Int
    let present: Int
    let absent: Int
    let leave: Int
    let error: String?

    // Optional extended fields returned by `/api/dashboard/overview` and newer dashboard builds.
    let notPunchedIn: Int?
    let cpVisitsCompleted: Int?
    let svVisitsCompleted: Int?
    let collectionTotal: Double?
    let collectionCount: Int?
    let bookingCount: Int?
    let registrationCount: Int?
    let leaveApproved: Int?
    let weekOff: Int?
    let permissionCount: Int?
    let wfhApproved: Int?
    let leadsHot: Int?
    let leadsWarm: Int?
    let leadsCold: Int?

    // Same-weekday-one-week-earlier baselines returned by `/api/mobile/dashboard`
    // (Android `MobileDashboardResponse.prev*`). Drive the marketing tiles'
    // "vs last week" trend pills. Nullable on purpose: a backend that predates
    // these fields returns nothing, and the pill is hidden rather than showing
    // an invented delta.
    let prevTotalCalls: Int?
    let prevIncomingCalls: Int?
    let prevOutboundCalls: Int?
    let prevHot: Int?
    let prevWarm: Int?
    let prevCold: Int?

    var leaveCount: Int { leaveApproved ?? leave }
    var hotLeadCount: Int { leadsHot ?? hot }
    var warmLeadCount: Int { leadsWarm ?? warm }
    var coldLeadCount: Int { leadsCold ?? cold }

    private enum CodingKeys: String, CodingKey {
        case success, date, totalCalls, incomingCalls, outboundCalls
        case hot, warm, cold, cpVisitsFixed, svVisitsFixed
        case totalStaff, present, absent, leave, error
        case notPunchedIn, cpVisitsCompleted, svVisitsCompleted
        case collectionTotal, collectionCount, bookingCount, registrationCount
        case leaveApproved, weekOff, permissionCount, wfhApproved
        case leadsHot, leadsWarm, leadsCold
        case prevTotalCalls, prevIncomingCalls, prevOutboundCalls
        case prevHot, prevWarm, prevCold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = container.decodeLossyBool(forKey: .success, defaultValue: false)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        totalCalls = container.decodeLossyInt(forKey: .totalCalls)
        incomingCalls = container.decodeLossyInt(forKey: .incomingCalls)
        outboundCalls = container.decodeLossyInt(forKey: .outboundCalls)
        hot = container.decodeLossyInt(forKey: .hot)
        warm = container.decodeLossyInt(forKey: .warm)
        cold = container.decodeLossyInt(forKey: .cold)
        cpVisitsFixed = container.decodeLossyInt(forKey: .cpVisitsFixed)
        svVisitsFixed = container.decodeLossyInt(forKey: .svVisitsFixed)
        totalStaff = container.decodeLossyInt(forKey: .totalStaff)
        present = container.decodeLossyInt(forKey: .present)
        absent = container.decodeLossyInt(forKey: .absent)
        leave = container.decodeLossyInt(forKey: .leave)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        notPunchedIn = container.decodeLossyOptionalInt(forKey: .notPunchedIn)
        cpVisitsCompleted = container.decodeLossyOptionalInt(forKey: .cpVisitsCompleted)
        svVisitsCompleted = container.decodeLossyOptionalInt(forKey: .svVisitsCompleted)
        collectionTotal = container.decodeLossyOptionalDouble(forKey: .collectionTotal)
        collectionCount = container.decodeLossyOptionalInt(forKey: .collectionCount)
        bookingCount = container.decodeLossyOptionalInt(forKey: .bookingCount)
        registrationCount = container.decodeLossyOptionalInt(forKey: .registrationCount)
        leaveApproved = container.decodeLossyOptionalInt(forKey: .leaveApproved)
        weekOff = container.decodeLossyOptionalInt(forKey: .weekOff)
        permissionCount = container.decodeLossyOptionalInt(forKey: .permissionCount)
        wfhApproved = container.decodeLossyOptionalInt(forKey: .wfhApproved)
        leadsHot = container.decodeLossyOptionalInt(forKey: .leadsHot)
        leadsWarm = container.decodeLossyOptionalInt(forKey: .leadsWarm)
        leadsCold = container.decodeLossyOptionalInt(forKey: .leadsCold)
        prevTotalCalls = container.decodeLossyOptionalInt(forKey: .prevTotalCalls)
        prevIncomingCalls = container.decodeLossyOptionalInt(forKey: .prevIncomingCalls)
        prevOutboundCalls = container.decodeLossyOptionalInt(forKey: .prevOutboundCalls)
        prevHot = container.decodeLossyOptionalInt(forKey: .prevHot)
        prevWarm = container.decodeLossyOptionalInt(forKey: .prevWarm)
        prevCold = container.decodeLossyOptionalInt(forKey: .prevCold)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyBool(forKey key: Key, defaultValue: Bool) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) { return intValue != 0 }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) { return true }
            if ["false", "0", "no"].contains(normalized) { return false }
        }
        return defaultValue
    }

    func decodeLossyInt(forKey key: Key, defaultValue: Int = 0) -> Int {
        decodeLossyOptionalInt(forKey: key) ?? defaultValue
    }

    func decodeLossyOptionalInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let double = try? decodeIfPresent(Double.self, forKey: key) { return Int(double) }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Int(trimmed) ?? Double(trimmed).map(Int.init)
        }
        return nil
    }

    func decodeLossyOptionalDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) { return Double(intValue) }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Double(trimmed)
        }
        return nil
    }
}
