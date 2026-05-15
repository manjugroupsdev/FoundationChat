import Foundation
import SwiftUI

/// Mirrors the Android `TodayVisit` payload returned by `GET /api/sitevisits/my`.
/// Field aliases handle the historical name variants the Convex backend has
/// emitted for the start/end times — see `Mconnect/network/GeoTrackApi.kt`.
struct ConvexSiteVisit: Decodable, Identifiable, Equatable, Sendable {
    let _id: String
    let clientPlaceId: String?
    let scheduledDate: String?
    let status: String?
    let placeName: String?
    let placeAddress: String?
    let placeType: String?
    let placeLat: Double?
    let placeLng: Double?
    let scheduledStartTime: String?
    let scheduledEndTime: String?
    let tripType: String?
    let clientPlaceVisitId: String?
    let leadName: String?
    let leadPhone: String?
    let cpVisit: ConvexCPVisitState?

    var id: String { _id }

    /// Canonical bucket (matches the Android `bindRow` mapping).
    var statusBucket: SiteVisitStatus {
        switch (status ?? "").lowercased() {
        case "completed": return .completed
        case "in-progress", "in_progress", "started", "active", "arrived":
            return .inProgress
        case "cancelled", "canceled": return .cancelled
        default: return .scheduled
        }
    }
}

struct ConvexCPVisitState: Decodable, Equatable, Sendable {
    let clientMet: Bool?
    let clientMetAt: Double?
    let clientNoShowReason: String?
    let outcome: String?
    let postponeReasons: [String]?
}

enum SiteVisitStatus: String, CaseIterable, Identifiable, Sendable {
    case all
    case scheduled
    case inProgress
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .secondary
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}
