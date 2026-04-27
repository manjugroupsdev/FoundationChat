import Foundation

// MARK: - Telecaller Leads

struct ConvexLead: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let leadId: String?
    let name: String?
    let phone: String?
    let alternatePhone: String?
    let email: String?
    let status: String?
    let segment: String?
    let source: String?
    let notes: String?
    let assignedTo: String?
    let assignedToName: String?
    let assignedAt: String?
    let lastContactedAt: String?
    let nextFollowUpAt: String?
    let createdAt: String?

    var id: String { _id }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let phone, !phone.isEmpty { return phone }
        return "Lead"
    }

    var displayPhone: String {
        phone ?? alternatePhone ?? "--"
    }

    var statusLabel: String {
        guard let status, !status.isEmpty else { return "New" }
        return status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

enum LeadMode: String, CaseIterable, Identifiable {
    case all
    case new
    case contacted
    case followUp
    case converted
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .new: return "New"
        case .contacted: return "Contacted"
        case .followUp: return "Follow-up"
        case .converted: return "Converted"
        case .closed: return "Closed"
        }
    }

    /// Server-side status filter token. `nil` means no filter (All).
    var statusFilter: String? {
        switch self {
        case .all: return nil
        case .new: return "new"
        case .contacted: return "contacted"
        case .followUp: return "follow_up"
        case .converted: return "converted"
        case .closed: return "closed"
        }
    }

    func matches(_ lead: ConvexLead) -> Bool {
        guard let token = statusFilter else { return true }
        let value = (lead.status ?? "new").lowercased()
        if value == token { return true }
        if self == .followUp && (value == "followup" || value == "follow-up") { return true }
        return false
    }
}
