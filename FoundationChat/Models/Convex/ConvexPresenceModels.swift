import Foundation

struct UserPresenceInfo: Decodable, Identifiable, Equatable, Sendable {
    let stackUserId: String
    let status: String
    let customStatusText: String?
    let customStatusEmoji: String?
    let lastHeartbeatAt: Double

    var id: String { stackUserId }

    var presenceStatus: PresenceStatus {
        PresenceStatus(rawValue: status) ?? .offline
    }
}

enum PresenceStatus: String, Sendable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case online
    case away
    case busy
    case offline

    var displayName: String {
        switch self {
        case .online: return "Online"
        case .away: return "Away"
        case .busy: return "Busy"
        case .offline: return "Offline"
        }
    }

    var systemImage: String {
        switch self {
        case .online: return "circle.fill"
        case .away: return "moon.fill"
        case .busy: return "minus.circle.fill"
        case .offline: return "circle"
        }
    }
}

struct HeartbeatResult: Decodable, Sendable {
    let status: String
}

struct SetStatusResult: Decodable, Sendable {
    let status: String
}

struct ClearStatusResult: Decodable, Sendable {
    let cleared: Bool
}
