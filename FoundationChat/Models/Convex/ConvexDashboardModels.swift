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
    let prevTotalCalls: Int?
    let prevIncomingCalls: Int?
    let prevOutboundCalls: Int?
    let prevHot: Int?
    let prevWarm: Int?
    let prevCold: Int?
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

    var leaveCount: Int { leaveApproved ?? leave }
    var hotLeadCount: Int { leadsHot ?? hot }
    var warmLeadCount: Int { leadsWarm ?? warm }
    var coldLeadCount: Int { leadsCold ?? cold }

    private enum CodingKeys: String, CodingKey {
        case success, date, totalCalls, incomingCalls, outboundCalls
        case hot, warm, cold, cpVisitsFixed, svVisitsFixed
        case totalStaff, present, absent, leave, error
        case prevTotalCalls, prevIncomingCalls, prevOutboundCalls
        case prevHot, prevWarm, prevCold
        case notPunchedIn, cpVisitsCompleted, svVisitsCompleted
        case collectionTotal, collectionCount, bookingCount, registrationCount
        case leaveApproved, weekOff, permissionCount, wfhApproved
        case leadsHot, leadsWarm, leadsCold
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
        prevTotalCalls = container.decodeLossyOptionalInt(forKey: .prevTotalCalls)
        prevIncomingCalls = container.decodeLossyOptionalInt(forKey: .prevIncomingCalls)
        prevOutboundCalls = container.decodeLossyOptionalInt(forKey: .prevOutboundCalls)
        prevHot = container.decodeLossyOptionalInt(forKey: .prevHot)
        prevWarm = container.decodeLossyOptionalInt(forKey: .prevWarm)
        prevCold = container.decodeLossyOptionalInt(forKey: .prevCold)
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
    }

    /// Same thin fallback Android uses when the aggregate dashboard route is
    /// unavailable: retain the live CP/SV counts and leave unavailable
    /// company-wide metrics at zero without inventing trend data.
    static func visitFallback(date: String, cpVisitsFixed: Int, svVisitsFixed: Int) -> Self {
        Self(
            success: true,
            date: date,
            totalCalls: 0,
            incomingCalls: 0,
            outboundCalls: 0,
            hot: 0,
            warm: 0,
            cold: 0,
            cpVisitsFixed: cpVisitsFixed,
            svVisitsFixed: svVisitsFixed,
            totalStaff: 0,
            present: 0,
            absent: 0,
            leave: 0,
            prevTotalCalls: nil,
            prevIncomingCalls: nil,
            prevOutboundCalls: nil,
            prevHot: nil,
            prevWarm: nil,
            prevCold: nil,
            error: nil,
            notPunchedIn: nil,
            cpVisitsCompleted: nil,
            svVisitsCompleted: nil,
            collectionTotal: nil,
            collectionCount: nil,
            bookingCount: nil,
            registrationCount: nil,
            leaveApproved: nil,
            weekOff: nil,
            permissionCount: nil,
            wfhApproved: nil,
            leadsHot: nil,
            leadsWarm: nil,
            leadsCold: nil
        )
    }

    private init(
        success: Bool,
        date: String?,
        totalCalls: Int,
        incomingCalls: Int,
        outboundCalls: Int,
        hot: Int,
        warm: Int,
        cold: Int,
        cpVisitsFixed: Int,
        svVisitsFixed: Int,
        totalStaff: Int,
        present: Int,
        absent: Int,
        leave: Int,
        prevTotalCalls: Int?,
        prevIncomingCalls: Int?,
        prevOutboundCalls: Int?,
        prevHot: Int?,
        prevWarm: Int?,
        prevCold: Int?,
        error: String?,
        notPunchedIn: Int?,
        cpVisitsCompleted: Int?,
        svVisitsCompleted: Int?,
        collectionTotal: Double?,
        collectionCount: Int?,
        bookingCount: Int?,
        registrationCount: Int?,
        leaveApproved: Int?,
        weekOff: Int?,
        permissionCount: Int?,
        wfhApproved: Int?,
        leadsHot: Int?,
        leadsWarm: Int?,
        leadsCold: Int?
    ) {
        self.success = success
        self.date = date
        self.totalCalls = totalCalls
        self.incomingCalls = incomingCalls
        self.outboundCalls = outboundCalls
        self.hot = hot
        self.warm = warm
        self.cold = cold
        self.cpVisitsFixed = cpVisitsFixed
        self.svVisitsFixed = svVisitsFixed
        self.totalStaff = totalStaff
        self.present = present
        self.absent = absent
        self.leave = leave
        self.prevTotalCalls = prevTotalCalls
        self.prevIncomingCalls = prevIncomingCalls
        self.prevOutboundCalls = prevOutboundCalls
        self.prevHot = prevHot
        self.prevWarm = prevWarm
        self.prevCold = prevCold
        self.error = error
        self.notPunchedIn = notPunchedIn
        self.cpVisitsCompleted = cpVisitsCompleted
        self.svVisitsCompleted = svVisitsCompleted
        self.collectionTotal = collectionTotal
        self.collectionCount = collectionCount
        self.bookingCount = bookingCount
        self.registrationCount = registrationCount
        self.leaveApproved = leaveApproved
        self.weekOff = weekOff
        self.permissionCount = permissionCount
        self.wfhApproved = wfhApproved
        self.leadsHot = leadsHot
        self.leadsWarm = leadsWarm
        self.leadsCold = leadsCold
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
