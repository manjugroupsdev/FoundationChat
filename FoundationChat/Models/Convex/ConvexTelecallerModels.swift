import Foundation

// MARK: - Telecaller Leads
//
// Field contract mirrors the Android `TelecallerLeadData`
// (app/.../network/ApiService.kt). The `api/telecaller/leads/my` response
// uses these exact JSON keys — the earlier iOS model decoded a different,
// non-existent shape (`name`/`phone`/`status`/…) so every row rendered empty.
// All fields are optional and decoded defensively: one unexpected/renamed
// field must never abort the whole list parse.

struct ConvexLead: Codable, Identifiable, Equatable, Sendable {
    let _id: String
    let source: String?
    let contactName: String?
    let mobileNumber: String?
    let mobileNumberNormalized: String?
    let emailId: String?
    let alternateNumber: String?
    let campaignName: String?
    let primaryCampaign: String?
    let secondaryCampaign: String?
    let assignedToStaffName: String?
    let assignedDate: String?
    let assignedTime: String?
    let assignedDateTime: Double?
    let leadReceivedAt: Double?
    let followUpStatus: String?
    let followUpRemarks: String?
    let followUpDate: Double?
    let clientCity: String?
    let locationPreferred: String?
    let budget: String?
    /// `_creationTime` from Convex (epoch millis).
    let creationTime: Double?

    private enum CodingKeys: String, CodingKey {
        case _id, id
        case source, contactName, mobileNumber, mobileNumberNormalized
        case emailId, alternateNumber, campaignName, primaryCampaign, secondaryCampaign
        case assignedToStaffName, assignedDate, assignedTime, assignedDateTime
        case leadReceivedAt, followUpStatus, followUpRemarks, followUpDate
        case clientCity, locationPreferred, budget
        case creationTime = "_creationTime"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `@SerializedName("_id", alternate = ["id"])` on Android.
        if let primary = try? c.decodeIfPresent(String.self, forKey: ._id) {
            _id = primary
        } else if let fallback = try? c.decodeIfPresent(String.self, forKey: .id) {
            _id = fallback
        } else {
            _id = UUID().uuidString
        }
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        contactName = try? c.decodeIfPresent(String.self, forKey: .contactName)
        mobileNumber = try? c.decodeIfPresent(String.self, forKey: .mobileNumber)
        mobileNumberNormalized = try? c.decodeIfPresent(String.self, forKey: .mobileNumberNormalized)
        emailId = try? c.decodeIfPresent(String.self, forKey: .emailId)
        alternateNumber = try? c.decodeIfPresent(String.self, forKey: .alternateNumber)
        campaignName = try? c.decodeIfPresent(String.self, forKey: .campaignName)
        primaryCampaign = try? c.decodeIfPresent(String.self, forKey: .primaryCampaign)
        secondaryCampaign = try? c.decodeIfPresent(String.self, forKey: .secondaryCampaign)
        assignedToStaffName = try? c.decodeIfPresent(String.self, forKey: .assignedToStaffName)
        assignedDate = try? c.decodeIfPresent(String.self, forKey: .assignedDate)
        assignedTime = try? c.decodeIfPresent(String.self, forKey: .assignedTime)
        assignedDateTime = try? c.decodeIfPresent(Double.self, forKey: .assignedDateTime)
        leadReceivedAt = try? c.decodeIfPresent(Double.self, forKey: .leadReceivedAt)
        followUpStatus = try? c.decodeIfPresent(String.self, forKey: .followUpStatus)
        followUpRemarks = try? c.decodeIfPresent(String.self, forKey: .followUpRemarks)
        followUpDate = try? c.decodeIfPresent(Double.self, forKey: .followUpDate)
        clientCity = try? c.decodeIfPresent(String.self, forKey: .clientCity)
        locationPreferred = try? c.decodeIfPresent(String.self, forKey: .locationPreferred)
        budget = try? c.decodeIfPresent(String.self, forKey: .budget)
        creationTime = try? c.decodeIfPresent(Double.self, forKey: .creationTime)
    }

    var id: String { _id }

    // MARK: Compatibility accessors (used across the Telecaller views)

    /// Contact name. Kept named `name` so the views read naturally.
    var name: String? { contactName }
    /// Primary phone.
    var phone: String? { mobileNumber }
    /// Secondary phone.
    var alternatePhone: String? { alternateNumber }
    /// Follow-up status is the lead's lifecycle state on this contract.
    var status: String? { followUpStatus }

    var displayName: String {
        if let contactName, !contactName.isEmpty { return contactName }
        if let mobileNumber, !mobileNumber.isEmpty { return mobileNumber }
        return "Unnamed lead"
    }

    var displayPhone: String {
        if let mobileNumber, !mobileNumber.isEmpty { return mobileNumber }
        if let alternateNumber, !alternateNumber.isEmpty { return alternateNumber }
        return "No phone"
    }

    var callPhone: String? {
        if let mobileNumber, !mobileNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return mobileNumber }
        if let alternateNumber, !alternateNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return alternateNumber }
        return nil
    }

    /// Mirrors Android's badge labelling in `MyLeadsFragment.bindRow`.
    var statusLabel: String {
        switch (followUpStatus ?? "").lowercased() {
        case "converted": return "Converted"
        case "closed": return "Closed"
        case "contacted": return "Contacted"
        case "pending": return "Pending"
        default: return "New"
        }
    }

    /// Formatted "received" timestamp, mirroring Android's
    /// `leadReceivedAt ?: assignedDateTime ?: createdAt` fallback chain.
    var receivedText: String? {
        let millis = leadReceivedAt ?? assignedDateTime ?? creationTime
        guard let millis, millis > 0 else { return nil }
        let date = Date(timeIntervalSince1970: millis / 1000)
        return ConvexLead.receivedFormatter.string(from: date)
    }

    /// Meta line matching Android: source · campaign · location · Received …
    var metaText: String {
        var parts: [String] = []
        if let source, !source.isEmpty {
            parts.append(source.prefix(1).uppercased() + String(source.dropFirst()))
        }
        if let campaign = (campaignName ?? primaryCampaign), !campaign.isEmpty {
            parts.append(campaign)
        }
        if let loc = (locationPreferred ?? clientCity), !loc.isEmpty {
            parts.append(loc)
        }
        if let receivedText {
            parts.append("Received \(receivedText)")
        }
        return parts.joined(separator: " · ")
    }

    private static let receivedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, h:mm a"
        f.locale = Locale.current
        return f
    }()
}

enum LeadMode: String, CaseIterable, Identifiable {
    case all
    case new
    case contacted
    case pending
    case converted
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .new: return "New"
        case .contacted: return "Contacted"
        case .pending: return "Pending"
        case .converted: return "Converted"
        case .closed: return "Closed"
        }
    }

    /// Server-side status filter token. `nil` means no filter (All).
    /// Android fetches everything and filters client-side, so this is only a
    /// hint — client-side `matches` is authoritative.
    var statusFilter: String? {
        switch self {
        case .all: return nil
        case .new: return "new"
        case .contacted: return "contacted"
        case .pending: return "pending"
        case .converted: return "converted"
        case .closed: return "closed"
        }
    }

    func matches(_ lead: ConvexLead) -> Bool {
        guard self != .all else { return true }
        // `null` follow-up status is treated as "new", matching Android.
        let value = (lead.followUpStatus ?? "new").lowercased()
        switch self {
        case .all: return true
        case .new: return value == "new" || value.isEmpty
        case .contacted: return value == "contacted"
        case .pending: return value == "pending"
        case .converted: return value == "converted"
        case .closed: return value == "closed"
        }
    }
}
