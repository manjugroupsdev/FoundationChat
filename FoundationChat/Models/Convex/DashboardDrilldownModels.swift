import Foundation

/// VP-dashboard drill-down rows: today's calls (`/api/dashboard/calls`) and
/// today's completed registrations (`/api/dashboard/registrations`). Field names
/// mirror the Android Retrofit models byte-for-byte.

struct DashboardCallRow: Codable, Identifiable, Sendable {
    let id: String
    let phoneNumber: String?
    let callType: String?
    let status: String?
    let agent: String?
    let duration: String?
    let talkTime: String?
    let time: String?
}

struct DashboardCallsResponse: Codable, Sendable {
    let success: Bool
    let calls: [DashboardCallRow]?
    let error: String?
}

struct DashboardRegistrationRow: Codable, Identifiable, Sendable {
    let id: String
    let clientName: String?
    let ownerName: String?
    let status: String?
    let completedDate: String?
    let scheduledDate: String?
    let notes: String?
}

struct DashboardRegistrationsResponse: Codable, Sendable {
    let success: Bool
    let registrations: [DashboardRegistrationRow]?
    let error: String?
}
